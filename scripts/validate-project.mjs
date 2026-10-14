import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const htmlFiles = fs.readdirSync(root).filter((name) => name.endsWith('.html'));
const sqlFiles = ['sql_setup.sql', 'supabase_admin_hardening.sql', 'fix_missing_rpcs.sql']
  .filter((name) => fs.existsSync(path.join(root, name)));
const errors = [];
const pages = new Map();

for (const file of htmlFiles) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  pages.set(file, source);
  const scripts = [...source.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)]
    .filter((match) => !/\bsrc\s*=/.test(match[1]))
    .map((match) => match[2])
    .filter((code) => code.trim());

  scripts.forEach((code, index) => {
    try {
      new Function(code);
    } catch (error) {
      errors.push(`JS syntax error in ${file}, inline script ${index + 1}: ${error.message}`);
    }
  });

  const ids = [...source.matchAll(/\bid=["']([^"']+)["']/g)].map((match) => match[1]);
  const seen = new Set();
  for (const id of ids) {
    if (seen.has(id)) errors.push(`Duplicate id "${id}" in ${file}`);
    seen.add(id);
  }

  for (const match of source.matchAll(/\b(?:href|src)=["']([^"']+)["']/gi)) {
    const url = match[1].trim();
    if (!url || /^(?:https?:|mailto:|tel:|data:|javascript:|#|\/\/)/i.test(url)) continue;
    const clean = url.split(/[?#]/, 1)[0];
    if (!clean) continue;
    if (/\.html$/i.test(clean) && !fs.existsSync(path.resolve(root, clean))) {
      errors.push(`Missing local page referenced by ${file}: ${url}`);
    }
    if (/\.js$/i.test(clean) && !fs.existsSync(path.resolve(root, clean))) {
      errors.push(`Missing local script referenced by ${file}: ${url}`);
    }
  }
}

const sql = sqlFiles.map((file) => fs.readFileSync(path.join(root, file), 'utf8')).join('\n');
const rpcDefinitions = new Set(
  [...sql.matchAll(/create\s+(?:or\s+replace\s+)?function\s+public\.([a-zA-Z0-9_]+)\s*\(/gi)]
    .map((match) => match[1])
);
const rpcCalls = new Set();
if (!/create\s+table\s+if\s+not\s+exists\s+public\.platform_admins/i.test(sql)) {
  errors.push('Missing platform_admins table required by is_platform_admin()');
}
if (!/revoke all on function public\.get_next_certificate_number\(\) from public, anon, authenticated/i.test(sql)) {
  errors.push('Certificate sequence helper is not restricted from direct client calls');
}
for (const [file, source] of pages) {
  for (const match of source.matchAll(/\.rpc\(\s*['"]([a-zA-Z0-9_]+)['"]/g)) {
    rpcCalls.add(match[1]);
    if (!rpcDefinitions.has(match[1])) errors.push(`RPC "${match[1]}" used in ${file} has no definition in the checked SQL files`);
  }
}

for (const file of sqlFiles) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  for (const tag of ['$$', '$fn$']) {
    const count = [...source.matchAll(new RegExp(tag.replace(/\$/g, '\\\\$'), 'g'))].length;
    if (count % 2 !== 0) errors.push(`Unbalanced ${tag} delimiters in ${file} (count: ${count})`);
  }
  if (/\bdo\s+\$(?!\$)/i.test(source) || /^\$;\s*$/m.test(source)) {
    errors.push(`Malformed dollar-quoted DO block marker in ${file}`);
  }
}

console.log(`Checked ${htmlFiles.length} HTML pages, ${rpcCalls.size} RPC names, and ${sqlFiles.length} SQL files.`);
if (errors.length) {
  console.error(errors.map((error) => `- ${error}`).join('\n'));
  process.exitCode = 1;
} else {
  console.log('Static validation passed.');
}
