#!/usr/bin/env node
// No network, credentials or production writes. Execute the real portal scripts
// against its actual HTML IDs with a small DOM adapter and explicit backend data.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'graduate-v2.html'), 'utf8');
const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)]
  .filter(m => !/\bsrc\s*=/i.test(m[1])).map(m => m[2]);

function fixture({membership = [], profile = true, error = null, hash = '', invalid = false, broken = false} = {}) {
  const nodes = new Map();
  function node(classes = '') {
    const tokens = new Set(classes.split(/\s+/).filter(Boolean));
    return {value: '', textContent: '', innerHTML: '', style: {}, dataset: {}, checked: false, disabled: false,
      classList: {add: x => tokens.add(x), remove: x => tokens.delete(x), contains: x => tokens.has(x),
        toggle(x, force) {const on = force === undefined ? !tokens.has(x) : force; on ? tokens.add(x) : tokens.delete(x); return on;}},
      listeners: {}, addEventListener(type, fn) {this.listeners[type]=fn;}, dispatchEvent() {}, querySelectorAll: () => [], scrollIntoView() {}};
  }
  // Only real markup, not template strings inside scripts, defines available IDs.
  const markup = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, '');
  for (const m of markup.matchAll(/<[^>]+\bid=["']([^"']+)["'][^>]*>/g)) {
    nodes.set(m[1], node(m[0].match(/\bclass=["']([^"']*)/)?.[1] || ''));
  }
  if (broken) nodes.delete('topLogoutBtn');
  const profileMarkup = markup.slice(markup.indexOf('id="profile"'), markup.indexOf('id="goldProfileCard"'));
  nodes.get('profile').contains = target => [...nodes].some(([id, value]) => value === target && profileMarkup.includes('id="' + id + '"'));
  const anchors = [...markup.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)].filter(m => /href=["']#/.test(m[1])).map(m => {
    const a = node(); a.href = m[1].match(/href=["']([^"']+)/)[1];
    a.getAttribute = key => key === 'href' ? a.href : null; return a;
  });
  const body = node();
  let user = null, listener = () => {};
  const reads = [], writes = [];
  const record = {id: 'fixture-profile', full_name: 'Fixture Graduate', phone: '01000000000',
    email: 'fixture@example.invalid', qualification: 'Fixture degree', bio: 'Fixture bio',
    publication_consent: false, public_profile_consent: false, digital_passport_public_consent: false};
  const authUser = {id: 'fixture-user', email: record.email, user_metadata: {}};
  const resultFor = table => {
    reads.push(table);
    if (table === 'graduate_profiles') return {data: profile ? record : null, error};
    if (table === 'graduate_membership_requests') return {data: membership, error: null};
    if (table === 'platform_notification_preferences') return {data: {email_enabled: true}, error: null};
    return {data: [], error: null};
  };
  const sb = {auth: {
    getUser: async () => ({data: {user}}),
    signInWithPassword: async () => {if (invalid) return {data: {}, error: new Error('Invalid login credentials')}; user = authUser; listener('SIGNED_IN'); return {data: {user}, error: null};},
    setSession: async () => {user = authUser; listener('SIGNED_IN'); return {data: {user}, error: null};},
    signOut: async () => {user = null; return {error: null};},
    onAuthStateChange: cb => {listener = cb;}
  }, storage: {from: () => ({createSignedUrl: async () => ({data: null, error: null})})}, functions: {invoke: async name => {reads.push(name); return {data: {access_token: 'fixture', refresh_token: 'fixture'}, error: null};}},
    from(table) {
      const q = new Proxy({}, {get(_, key) {
        if (key === 'then') return (resolve, reject) => Promise.resolve(resultFor(table)).then(resolve, reject);
        if (['update', 'insert', 'upsert', 'delete'].includes(key)) return () => {writes.push(table); throw Error('Unexpected write');};
        return () => q;
      }}); return q;
    }, rpc: async name => {reads.push(name); return {data: name === 'current_alumni_profile_id' ? null : [], error: null};}
  };
  const scheduled = [];
  const context = vm.createContext({console, URL, Date, Event: class {}, location: {href: 'https://example.invalid/graduate-v2.html', hash},
    document: {body, getElementById: id => nodes.get(id) || null, querySelectorAll: selector => selector.includes('a') ? anchors : [], querySelector: () => null}, history: {replaceState() {}},
    supabase: {createClient: () => sb}, setTimeout: fn => scheduled.push(fn)});
  context.window = context;
  context.addEventListener = () => {};
  for (const script of scripts) vm.runInContext(script, context, {filename: 'graduate-v2.html'});
  return {context, nodes, body, reads, writes, scheduled, anchors, async drain() {
    await new Promise(resolve => setImmediate(resolve));
    for (const callback of scheduled.splice(0)) await callback();
    await new Promise(resolve => setImmediate(resolve));
  }};
}

(async () => {
  let passed = 0;
  async function test(name, opts, check) {
    const f = fixture(opts); await f.drain();
    f.nodes.get('loginIdentifier').value = opts.identifier || 'fixture@example.invalid';
    f.nodes.get('loginPassword').value = 'not-a-real-password';
    await f.context.loginGraduate(); await f.drain();
    await check(f); assert.deepEqual(f.writes, []); console.log('PASS ' + name); passed++;
  }
  function signedIn(f, gold, profileView = false) {
    assert.ok(!f.nodes.get('authMsg').textContent.includes('تعذر تسجيل الدخول'), f.nodes.get('authMsg').textContent);
    assert.ok(f.body.classList.contains('graduate-authenticated'));
    assert.ok(f.nodes.get('auth').classList.contains('hidden'));
    assert.ok(!f.nodes.get('topLogoutBtn').classList.contains('hidden'));
    assert.equal(f.nodes.get('name').value, 'Fixture Graduate');
    assert.equal(f.nodes.get('profile').classList.contains('hidden'), !profileView);
    assert.equal(f.nodes.get('dashboardHome').classList.contains('hidden'), profileView);
    assert.equal(f.nodes.get('goldFields').classList.contains('premium-locked'), !gold);
    assert.ok(f.reads.includes('graduate_my_certificates'), 'signed-in path must reach certificates, not merely suppress the error');
    assert.ok(f.reads.includes('platform_notification_preferences'));
    if (gold) {
      assert.ok(f.reads.includes('job_announcements'), 'gold jobs must load after login');
      assert.ok(f.reads.includes('alumni_notifications'), 'gold notifications must load after login');
      for (const id of ['jobsList','myJobApplicationsList','notificationsList','accessRequests'])
        assert.ok(!f.nodes.get(id).textContent.includes('جاري تحميل'), id + ' stuck loading');
    }
    for (const anchor of f.anchors) {
      // Reset to home then invoke the exact click listener bound to each real link.
      f.context.setGraduateMainView('home');
      let prevented = false;
      anchor.listeners.click?.({preventDefault() {prevented = true;}});
      const route = f.context.graduateSectionRoute(anchor.href), target = f.nodes.get(route.slice(1));
      if (!target) continue;
      assert.ok(prevented, 'unbound anchor: ' + anchor.href);
      assert.ok(!target.classList.contains('hidden'), 'hidden destination: ' + anchor.href);
      if (f.nodes.get('profile').contains(target))
        assert.ok(!f.nodes.get('profile').classList.contains('hidden'), 'hidden parent: ' + anchor.href);
    }
    f.context.setGraduateMainView('profile');
    assert.ok(!f.nodes.get('profile').classList.contains('hidden'));
    f.context.setGraduateMainView('home');
    assert.ok(!f.nodes.get('dashboardHome').classList.contains('hidden'));
  }
  await test('basic email login and signed-in event', {}, f => signedIn(f, false));
  await test('gold membership and profile deep link', {hash: '#profile', membership: [{status: 'approved', ends_at: '2099-01-01', created_at: '2026-01-01'}]}, f => signedIn(f, true, true));
  await test('pending membership phone login', {identifier: '01000000000', membership: [{status: 'pending', created_at: '2026-01-01'}]}, f => signedIn(f, false));
  await test('name login', {identifier: 'Fixture Graduate'}, f => signedIn(f, false));
  await test('missing graduate profile signs out safely', {profile: false}, f => {
    assert.ok(!f.body.classList.contains('graduate-authenticated'));
    assert.ok(!f.nodes.get('auth').classList.contains('hidden'));
    assert.ok(f.nodes.get('topLogoutBtn').classList.contains('hidden'));
    assert.ok(f.nodes.get('authMsg').textContent.includes('لا يوجد حساب خريج'));
  });
  await test('invalid credentials stay signed out', {invalid: true}, f => {
    assert.ok(!f.body.classList.contains('graduate-authenticated'));
    assert.ok(!f.nodes.get('auth').classList.contains('hidden'));
    assert.ok(f.nodes.get('authMsg').textContent.includes('بيانات الدخول غير صحيحة'));
  });
  // Mutation check: prove this harness notices missing DOM on the signed-in path.
  await test('missing current logout control is detected', {broken: true, invalid: true}, async f => {
    const sb = vm.runInContext('sb', f.context);
    await sb.auth.setSession({});
    await assert.rejects(f.context.load(), /classList/);
    f.scheduled.length = 0;
  });
  console.log(`${passed} graduate auth regression cases passed (mock backend, no real account login).`);
})().catch(error => {console.error(error); process.exitCode = 1;});
