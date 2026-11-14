import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://shahadatyofficial.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizeEgyptianPhone(value: string): string | null {
  const map: Record<string, string> = {
    "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
    "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9",
  };
  let digits = value.replace(/[٠-٩۰-۹]/g, (d) => map[d]).replace(/[^0-9]/g, "");
  if (digits.startsWith("0020")) digits = digits.slice(2);
  if (digits.startsWith("0")) digits = "20" + digits.slice(1);
  if (!digits.startsWith("20") && digits.length === 10 && digits.startsWith("1")) digits = "20" + digits;
  const phone = "+" + digits;
  return /^\+201[0125]\d{8}$/.test(phone) ? phone : null;
}

// Best-effort per-worker throttle. Supabase Auth also enforces password sign-in rate limits.
const attempts = new Map<string, { count: number; resetAt: number }>();
function rateLimited(ip: string): boolean {
  const now = Date.now();
  const current = attempts.get(ip);
  if (!current || current.resetAt <= now) {
    attempts.set(ip, { count: 1, resetAt: now + 10 * 60 * 1000 });
    return false;
  }
  current.count += 1;
  return current.count > 8;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    const origin = req.headers.get("origin");
    if (origin && origin !== allowedOrigin) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "LOGIN_FAILED" }, 405);
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return json({ error: "LOGIN_FAILED" }, 403);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
  if (!url || !anonKey || !serviceKey) return json({ error: "SERVER_NOT_CONFIGURED" }, 500);
  if (req.headers.get("apikey") !== anonKey) return json({ error: "LOGIN_FAILED" }, 401);

  const ip = (req.headers.get("x-forwarded-for") || "unknown").split(",")[0].trim().slice(0, 80);
  if (rateLimited(ip)) return json({ error: "LOGIN_FAILED" }, 429);

  let body: { phone?: string; password?: string };
  try {
    const raw = await req.text();
    if (raw.length > 3000) return json({ error: "LOGIN_FAILED" }, 400);
    body = JSON.parse(raw);
  } catch {
    return json({ error: "LOGIN_FAILED" }, 400);
  }
  const phone = normalizeEgyptianPhone(String(body.phone || ""));
  const password = String(body.password || "");
  if (!phone || password.length < 1 || password.length > 72) return json({ error: "LOGIN_FAILED" }, 401);

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: company, error: companyError } = await admin
    .from("companies")
    .select("id,auth_user_id")
    .eq("contact_phone", phone)
    .eq("status", "approved")
    .maybeSingle();

  // Keep the response identical for unknown, pending, suspended, or unlinked companies.
  if (companyError || !company?.auth_user_id) return json({ error: "LOGIN_FAILED" }, 401);

  const { data: authResult, error: userError } = await admin.auth.admin.getUserById(company.auth_user_id);
  const email = String(authResult?.user?.email || "").trim().toLowerCase();
  if (userError || !email) return json({ error: "LOGIN_FAILED" }, 401);

  const authClient = createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: login, error: loginError } = await authClient.auth.signInWithPassword({ email, password });
  if (loginError || !login.session) return json({ error: "LOGIN_FAILED" }, 401);

  return json({
    access_token: login.session.access_token,
    refresh_token: login.session.refresh_token,
    token_type: login.session.token_type,
    expires_in: login.session.expires_in,
  });
});
