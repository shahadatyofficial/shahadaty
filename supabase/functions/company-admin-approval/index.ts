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
  const digitsMap: Record<string, string> = {
    "٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9",
    "۰":"0","۱":"1","۲":"2","۳":"3","۴":"4","۵":"5","۶":"6","۷":"7","۸":"8","۹":"9",
  };
  let digits = value.replace(/[٠-٩۰-۹]/g, (d) => digitsMap[d]).replace(/[^0-9]/g, "");
  if (digits.startsWith("0020")) digits = digits.slice(2);
  if (digits.startsWith("0")) digits = "20" + digits.slice(1);
  if (!digits.startsWith("20") && digits.length === 10 && digits.startsWith("1")) digits = "20" + digits;
  if (!/^20\d{9,10}$/.test(digits)) return null;
  return "+" + digits;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    const origin = req.headers.get("origin");
    if (origin && origin !== allowedOrigin) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  const origin = req.headers.get("origin");
  if (origin && origin !== allowedOrigin) return json({ error: "ORIGIN_NOT_ALLOWED" }, 403);

  const authorization = req.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
  if (!authorization || !url || !anonKey || !serviceKey) return json({ error: "SERVER_NOT_CONFIGURED" }, 500);

  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await caller.auth.getUser();
  if (authError || !authData.user) return json({ error: "AUTH_REQUIRED" }, 401);
  const { data: isAdmin, error: adminError } = await caller.rpc("is_platform_admin");
  if (adminError || isAdmin !== true) return json({ error: "ADMIN_ONLY" }, 403);

  let body: { company_id?: string };
  try {
    const raw = await req.text();
    if (raw.length > 2000) return json({ error: "REQUEST_TOO_LARGE" }, 413);
    body = JSON.parse(raw);
  } catch {
    return json({ error: "INVALID_JSON" }, 400);
  }
  if (!body.company_id || !/^[0-9a-f-]{36}$/i.test(body.company_id)) {
    return json({ error: "COMPANY_ID_REQUIRED" }, 400);
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: company, error: companyError } = await admin
    .from("companies")
    .select("id,company_name,contact_email,contact_phone,auth_user_id,status")
    .eq("id", body.company_id)
    .maybeSingle();
  if (companyError || !company) return json({ error: "COMPANY_NOT_FOUND" }, 404);
  const email = String(company.contact_email || "").trim().toLowerCase();
  const phone = normalizeEgyptianPhone(String(company.contact_phone || ""));
  if (!email || !email.includes("@")) return json({ error: "COMPANY_EMAIL_REQUIRED" }, 400);
  if (!phone) return json({ error: "INVALID_COMPANY_PHONE: راجع رقم الهاتف المسجل؛ يجب أن يكون رقمًا مصريًا صحيحًا." }, 400);

  let authUser: any = null;
  if (company.auth_user_id) {
    const { data, error } = await admin.auth.admin.getUserById(company.auth_user_id);
    if (!error) authUser = data.user;
  }
  if (authUser && String(authUser.email || '').toLowerCase() !== email) {
    return json({ error: 'LINKED_ACCOUNT_EMAIL_MISMATCH: البريد المسجل بالشركة لا يطابق البريد المرتبط بحساب الدخول.' }, 409);
  }
  if (!authUser) {
    const { data, error } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (error) return json({ error: "AUTH_USER_LOOKUP_FAILED" }, 502);
    authUser = (data.users || []).find((u: any) => String(u.email || "").toLowerCase() === email) || null;
  }
  if (!authUser) return json({ error: "AUTH_ACCOUNT_NOT_FOUND: يجب أن تسجل الشركة حسابها أولًا بنفس البريد الإلكتروني المسجل." }, 409);

  const { data: allCompanies, error: companiesError } = await admin
    .from("companies").select("id,auth_user_id,contact_phone").neq("id", company.id);
  if (companiesError) return json({ error: "COMPANY_CONFLICT_CHECK_FAILED" }, 502);
  if ((allCompanies || []).some((c: any) => c.auth_user_id === authUser.id)) {
    return json({ error: "AUTH_ACCOUNT_ALREADY_LINKED_TO_ANOTHER_COMPANY" }, 409);
  }
  if ((allCompanies || []).some((c: any) => normalizeEgyptianPhone(String(c.contact_phone || "")) === phone)) {
    return json({ error: "PHONE_ALREADY_USED_BY_ANOTHER_COMPANY" }, 409);
  }

  // Phone login is handled by company-phone-login using the approved company record.
  // Do not write Auth phone fields: this flow must work with the Phone provider disabled.
  const { error: updateAuthError } = await admin.auth.admin.updateUserById(authUser.id, {
    email_confirm: true,
  });
  if (updateAuthError) {
    console.error("company auth update failed", updateAuthError.message);
    return json({ error: "AUTH_CONTACT_UPDATE_FAILED: تعذر تأكيد البريد والهاتف. تحقق من عدم استخدام الهاتف بحساب آخر." }, 409);
  }

  const { error: updateCompanyError } = await admin.from("companies").update({
    auth_user_id: authUser.id,
    status: "approved",
    contact_phone: phone,
  }).eq("id", company.id);
  if (updateCompanyError) {
    console.error("company approval update failed", updateCompanyError.message);
    return json({ error: "COMPANY_APPROVAL_UPDATE_FAILED" }, 500);
  }

  return json({
    success: true,
    company_id: company.id,
    auth_user_id: authUser.id,
    status: "approved",
    phone_login_enabled: true,
  });
});
