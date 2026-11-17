import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://shahadatyofficial.github.io";
const cors = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });
function normalizePhone(value: string) {
  let d = value.replace(/[٠-٩۰-۹]/g, x => String("٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹".indexOf(x) % 10)).replace(/[^0-9]/g, "");
  if (d.startsWith("0020")) d = d.slice(2);
  if (d.startsWith("20")) d = "0" + d.slice(2);
  if (d.length === 10 && d.startsWith("1")) d = "0" + d;
  return /^01[0125]\d{8}$/.test(d) ? d : null;
}
async function phoneAlreadyUsed(admin: any, mobile: string) {
  for (const table of ["graduate_profiles", "graduate_access_requests"]) {
    let from = 0;
    while (from < 20000) {
      let query = admin.from(table).select("phone").not("phone", "is", null).range(from, from + 999);
      if (table === "graduate_access_requests") query = query.in("status", ["pending", "approved"]);
      const { data, error } = await query;
      if (error) throw error;
      if ((data || []).some((row: any) => normalizePhone(String(row.phone || "")) === mobile)) return true;
      if (!data || data.length < 1000) break;
      from += 1000;
    }
  }
  return false;
}
async function hashToken(token: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest)).map(x => x.toString(16).padStart(2, "0")).join("");
}
function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  bytes.forEach(x => binary += String.fromCharCode(x));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
const attempts = new Map<string, { count: number; reset: number }>();
function rateLimited(key: string, limit = 8) {
  const now = Date.now(), prior = attempts.get(key);
  if (!prior || prior.reset <= now) { attempts.set(key, { count: 1, reset: now + 600000 }); return false; }
  prior.count++;
  return prior.count > limit;
}
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  if (req.method === "OPTIONS") {
    if (origin && origin !== allowedOrigin) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") return reply({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (origin && origin !== allowedOrigin) return reply({ error: "FORBIDDEN" }, 403);

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (!url || !anon || !secret) return reply({ error: "SERVER_CONFIGURATION" }, 500);
  let body: any;
  try { const raw = await req.text(); if (raw.length > 6000) return reply({ error: "INVALID_REQUEST" }, 400); body = JSON.parse(raw); }
  catch { return reply({ error: "INVALID_REQUEST" }, 400); }

  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  const action = String(body?.action || "");

  if (action === "create_claim") {
    const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
    // The Supabase gateway validates the project API key before invoking this function.
    // Do not compare the browser's legacy anon JWT byte-for-byte with the runtime
    // SUPABASE_ANON_KEY: projects migrating to publishable/secret keys can expose
    // a valid authenticated request while these two representations differ.
    if (!bearer) return reply({ error: "UNAUTHORIZED" }, 401);
    const caller = createClient(url, anon, { global: { headers: { Authorization: "Bearer " + bearer } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await caller.auth.getUser(bearer);
    if (authError || !authData.user) {
      console.error("graduate claim caller authentication failed", authError?.message || "user not found");
      return reply({ error: "UNAUTHORIZED" }, 401);
    }

    const institutionId = String(body.institution_id || "");
    const traineeId = String(body.trainee_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(institutionId) || !/^[0-9a-f-]{36}$/i.test(traineeId)) return reply({ error: "INVALID_REQUEST" }, 400);
    const { data: trainee, error: traineeError } = await admin.from("institution_trainees")
      .select("id,institution_id,branch_id,full_name,phone,status")
      .eq("id", traineeId).eq("institution_id", institutionId).maybeSingle();
    if (traineeError) {
      console.error("graduate claim trainee lookup failed", traineeError.message);
      return reply({ error: "TRAINEE_LOOKUP_FAILED" }, 500);
    }
    if (!trainee || trainee.status !== "active" || !normalizePhone(String(trainee.phone || ""))) {
      return reply({ error: "TRAINEE_NOT_READY", message: "تأكد من أن المتدرب نشط ورقم هاتفه المصري صحيح." }, 400);
    }
    const { data: permitted, error: permissionError } = await caller.rpc("institution_has_permission", {
      p_institution_id: institutionId, p_permission: "trainees.manage", p_branch_id: trainee.branch_id || null,
    });
    if (permissionError) {
      console.error("graduate claim permission check failed", permissionError.message);
      return reply({ error: "PERMISSION_CHECK_FAILED" }, 500);
    }
    if (permitted !== true) return reply({ error: "TRAINEE_MANAGEMENT_FORBIDDEN" }, 403);
    const { data: institution, error: institutionError } = await admin.from("institutions").select("status").eq("id", institutionId).maybeSingle();
    if (institutionError) {
      console.error("graduate claim institution lookup failed", institutionError.message);
      return reply({ error: "INSTITUTION_LOOKUP_FAILED" }, 500);
    }
    if (institution?.status !== "approved") return reply({ error: "INSTITUTION_NOT_ACTIVE" }, 403);

    const rawToken = randomToken(), tokenHash = await hashToken(rawToken), now = new Date().toISOString();
    const { error: revokeError } = await admin.from("graduate_account_claims").update({ consumed_at: now }).eq("trainee_id", traineeId).is("consumed_at", null);
    if (revokeError) {
      console.error("graduate claim previous token revoke failed", revokeError.message);
      return reply({ error: "CLAIM_PREPARE_FAILED" }, 500);
    }
    const { data: claim, error: insertError } = await admin.from("graduate_account_claims")
      .insert({ institution_id: institutionId, trainee_id: traineeId, token_hash: tokenHash, created_by: authData.user.id })
      .select("expires_at").single();
    if (insertError || !claim) {
      console.error("graduate claim insert failed", insertError?.message || "no row returned");
      return reply({ error: "CLAIM_CREATE_FAILED" }, 500);
    }
    return reply({ success: true, claim_code: rawToken, expires_at: claim.expires_at });
  }

  if (action === "redeem") {
    const ip = (req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for") || "unknown").split(",")[0].slice(0, 80);
    if (rateLimited("claim:" + ip, 10)) return reply({ error: "RATE_LIMITED" }, 429);
    const token = String(body.claim_code || "").trim();
    const password = String(body.password || "");
    if (!/^[A-Za-z0-9_-]{40,50}$/.test(token) || password.length < 10 || password.length > 72) {
      return reply({ error: "INVALID_CLAIM", message: "رمز الاستلام أو كلمة المرور غير صحيحة. كلمة المرور يجب ألا تقل عن 10 أحرف." }, 400);
    }
    const tokenHash = await hashToken(token);
    const { data: claim } = await admin.from("graduate_account_claims")
      .select("id,trainee_id,expires_at,consumed_at")
      .eq("token_hash", tokenHash).is("consumed_at", null).gt("expires_at", new Date().toISOString()).maybeSingle();
    if (!claim) return reply({ error: "CLAIM_INVALID_OR_EXPIRED", message: "رمز الاستلام غير صالح أو منتهي أو تم استخدامه." }, 400);
    const { data: trainee, error: traineeError } = await admin.from("institution_trainees")
      .select("id,full_name,phone,email,governorate,institution_id,status")
      .eq("id", claim.trainee_id).maybeSingle();
    if (traineeError || !trainee || trainee.status !== "active") return reply({ error: "TRAINEE_NOT_FOUND" }, 404);
    const mobile = normalizePhone(String(trainee.phone || ""));
    if (!mobile) return reply({ error: "PHONE_REQUIRED" }, 400);

    let alreadyUsed = false;
    try { alreadyUsed = await phoneAlreadyUsed(admin, mobile); }
    catch { return reply({ error: "DUPLICATE_CHECK_FAILED" }, 500); }
    if (alreadyUsed) {
      return reply({ error: "ACCOUNT_EXISTS", message: "رقم الهاتف مرتبط بالفعل بحساب أو طلب خريج. استخدم تسجيل الدخول أو تواصل مع الإدارة لربط السجل." }, 409);
    }

    const consumedAt = new Date().toISOString();
    const { data: consumed, error: consumeError } = await admin.from("graduate_account_claims")
      .update({ consumed_at: consumedAt }).eq("id", claim.id).is("consumed_at", null)
      .gt("expires_at", consumedAt).select("id").maybeSingle();
    if (consumeError || !consumed) return reply({ error: "CLAIM_ALREADY_USED" }, 409);

    const suppliedEmail = String(trainee.email || "").trim().toLowerCase();
    const email = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(suppliedEmail)
      ? suppliedEmail : "graduate-" + crypto.randomUUID() + "@accounts.shahadaty.invalid";
    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email, password, email_confirm: true,
      app_metadata: { account_type: "graduate", graduate_admin_approved: false, account_claimed: true },
      user_metadata: { full_name: trainee.full_name, phone: mobile, account_type: "graduate", approval_status: "pending" },
    });
    if (createError || !created.user) {
      await admin.from("graduate_account_claims").update({ consumed_at: null }).eq("id", claim.id).eq("consumed_at", consumedAt);
      return reply({ error: "ACCOUNT_CREATE_FAILED", message: "تعذر إنشاء الحساب. تأكد من عدم استخدام البريد الإلكتروني في حساب آخر." }, 409);
    }
    const { error: requestInsertError } = await admin.from("graduate_access_requests").insert({
      auth_user_id: created.user.id, full_name: trainee.full_name, email, phone: mobile,
      governorate: trainee.governorate || null, center: null, status: "pending",
    });
    if (requestInsertError) {
      await admin.auth.admin.deleteUser(created.user.id);
      await admin.from("graduate_account_claims").update({ consumed_at: null }).eq("id", claim.id).eq("consumed_at", consumedAt);
      return reply({ error: "REQUEST_SAVE_FAILED", message: "تعذر حفظ طلب المراجعة. يمكنك إعادة استخدام رمز الاستلام." }, 500);
    }
    return reply({ success: true, status: "pending", phone: mobile,
      message: "تم استلام طلبك. الحساب بانتظار مراجعة الإدارة، وبعد الموافقة يمكنك الدخول برقم هاتفك وكلمة المرور التي اخترتها." });
  }
  return reply({ error: "INVALID_ACTION" }, 400);
});
