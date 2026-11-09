import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://shahadatyofficial.github.io",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);

const corsFor = (origin: string) => ({
  "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://shahadatyofficial.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});

const json = (status: number, body: Record<string, unknown>, origin: string) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsFor(origin), "Content-Type": "application/json" },
  });

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function findUserByIdentifier(admin: any, identifier: { email?: string; phone?: string }) {
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = data?.users || [];
    const found = users.find((user: any) =>
      (identifier.email && String(user.email || "").toLowerCase() === identifier.email) ||
      (identifier.phone && user.phone === identifier.phone)
    );
    if (found) return found;
    if (users.length < 1000) return null;
  }
  throw new Error("تعذر البحث عن الحساب الحالي بأمان. تواصل مع الدعم.");
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsFor(origin) });
  if (req.method !== "POST") return json(405, { ok: false, message: "Method not allowed" }, origin);
  if (origin && !allowedOrigins.has(origin)) {
    return json(403, { ok: false, message: "مصدر الطلب غير مسموح." }, origin);
  }

  try {
    const body = await req.json();
    const email = body?.email == null ? null : String(body.email).trim().toLowerCase();
    const phone = String(body?.phone || "").trim();
    const password = String(body?.password || "");

    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      return json(400, { ok: false, message: "راجع البريد الإلكتروني أو اتركه فارغًا." }, origin);
    }
    if (!/^\+20(10|11|12|15)\d{8}$/.test(phone)) {
      return json(400, { ok: false, message: "رقم الهاتف المصري غير صحيح." }, origin);
    }
    if (password.length < 8 || password.length > 128) {
      return json(400, { ok: false, message: "كلمة المرور يجب ألا تقل عن 8 أحرف." }, origin);
    }
    if (!email && !phone) {
      return json(400, { ok: false, message: "أدخل البريد الإلكتروني أو رقم الهاتف." }, origin);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      throw new Error("إعدادات خدمة التسجيل غير مكتملة.");
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const publicAuth = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const identifierHash = await sha256(phone);
    const { data: allowed, error: rateLimitError } = await admin.rpc(
      "consume_institution_signup_limit",
      { p_identifier_hash: identifierHash },
    );
    if (rateLimitError) throw rateLimitError;
    if (allowed !== true) {
      return json(429, { ok: false, message: "تم تجاوز عدد محاولات التسجيل. انتظر 15 دقيقة ثم حاول مرة أخرى." }, origin);
    }

    const credentials = [
      ...(email ? [{ email, password }] : []),
      { phone, password },
    ];

    let existingUser: any = null;
    let verifiedByPassword = false;
    let lastAuthError: any = null;

    for (const credential of credentials) {
      const { data, error } = await publicAuth.auth.signInWithPassword(credential as any);
      if (!error && data?.user) {
        existingUser = data.user;
        verifiedByPassword = true;
        break;
      }
      lastAuthError = error;
      const code = String(error?.code || "").toLowerCase();
      if (code === "email_not_confirmed" || code === "phone_not_confirmed") {
        existingUser = await findUserByIdentifier(admin, "email" in credential ? { email } : { phone });
        if (existingUser) {
          verifiedByPassword = true;
          break;
        }
      }
    }

    if (existingUser && verifiedByPassword) {
      const currentEmail = String(existingUser.email || "").toLowerCase();
      const currentPhone = String(existingUser.phone || "");
      if (email && currentEmail && currentEmail !== email) {
        return json(409, { ok: false, message: "هذا الهاتف مرتبط بحساب آخر. سجل الدخول ببيانات الحساب المرتبط به." }, origin);
      }
      if (currentPhone && currentPhone !== phone) {
        return json(409, { ok: false, message: "هذا البريد مرتبط بحساب له رقم هاتف مختلف. تواصل مع الإدارة لتحديث البيانات." }, origin);
      }

      const attributes: Record<string, unknown> = {
        phone,
        phone_confirm: true,
      };
      if (email) {
        attributes.email = email;
        attributes.email_confirm = true;
      }
      const { error: updateError } = await admin.auth.admin.updateUserById(existingUser.id, attributes as any);
      if (updateError) throw updateError;
      return json(200, { ok: true, existing: true }, origin);
    }

    const attributes: Record<string, unknown> = {
      phone,
      phone_confirm: true,
      password,
      user_metadata: { signup_source: "institution_registration" },
    };
    if (email) {
      attributes.email = email;
      attributes.email_confirm = true;
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser(attributes as any);
    if (createError) {
      const message = String(createError.message || "").toLowerCase();
      if (message.includes("already") || message.includes("registered") || message.includes("exists") ||
          createError.code === "user_already_exists" || createError.code === "email_exists" || createError.code === "phone_exists") {
        return json(409, { ok: false, message: "يوجد حساب مسجل بهذه البيانات. استخدم كلمة المرور الصحيحة أو تواصل مع الدعم." }, origin);
      }
      throw createError;
    }
    if (!created?.user) throw new Error("تعذر إنشاء حساب المؤسسة.");
    return json(200, { ok: true, existing: false }, origin);
  } catch (error) {
    console.error("institution-register-auth:", error?.message || error);
    return json(500, { ok: false, message: "تعذر تجهيز حساب المؤسسة حاليًا. حاول مرة أخرى بعد قليل." }, origin);
  }
});
