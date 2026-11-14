import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://shahadatyofficial.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
function reply(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}
function getSecretKey(): string {
  const direct = Deno.env.get("SUPABASE_SECRET_KEY") || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (direct) return direct;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") || "{}");
    return String(keys.default || "");
  } catch {
    return "";
  }
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    const origin = req.headers.get("origin");
    if (origin && origin !== allowedOrigin) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return reply({ error: "FORBIDDEN" }, 403);

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  const secretKey = getSecretKey();
  if (!url || !anonKey || !secretKey || !token) return reply({ error: "UNAUTHORIZED" }, 401);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: callerData, error: callerError } = await caller.auth.getUser(token);
  if (callerError || !callerData.user) return reply({ error: "UNAUTHORIZED" }, 401);

  const { data: isAdmin, error: adminCheckError } = await caller.rpc("is_platform_admin");
  if (adminCheckError || isAdmin !== true) return reply({ error: "ADMIN_ONLY" }, 403);

  let body: { user_id?: string };
  try {
    const raw = await req.text();
    if (raw.length > 2000) return reply({ error: "INVALID_REQUEST" }, 400);
    body = JSON.parse(raw);
  } catch {
    return reply({ error: "INVALID_REQUEST" }, 400);
  }
  const userId = String(body.user_id || "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
    return reply({ error: "INVALID_USER_ID" }, 400);
  }

  const admin = createClient(url, secretKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: targetResult, error: targetError } = await admin.auth.admin.getUserById(userId);
  const target = targetResult?.user;
  if (targetError || !target || !target.email) return reply({ error: "GRADUATE_ACCOUNT_NOT_FOUND" }, 404);
  if (target.email_confirmed_at) {
    return reply({ success: true, already_confirmed: true, email: target.email });
  }

  const appMetadata = {
    ...(target.app_metadata || {}),
    email_confirmed_by_admin: true,
    email_confirmed_by_admin_id: callerData.user.id,
    email_confirmed_by_admin_at: new Date().toISOString(),
  };
  const { data: updated, error: updateError } = await admin.auth.admin.updateUserById(userId, {
    email_confirm: true,
    app_metadata: appMetadata,
  });
  if (updateError || !updated.user) {
    return reply({ error: updateError?.message || "CONFIRMATION_FAILED" }, 500);
  }
  return reply({ success: true, already_confirmed: false, email: updated.user.email });
});
