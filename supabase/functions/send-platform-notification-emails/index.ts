import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigin = "https://shahadatyofficial.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}
function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char] || char);
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

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY") || req.headers.get("apikey");
  const authorization = req.headers.get("Authorization");
  const cronSecret = req.headers.get("x-cron-secret");
  if (!supabaseUrl || !anonKey) return json({ error: "SERVICE_NOT_CONFIGURED" }, 503);

  const globalHeaders: Record<string, string> = {};
  if (authorization) globalHeaders.Authorization = authorization;
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: globalHeaders },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let authorized = false;
  if (authorization) {
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (!userError && userData.user) {
      const { data: isAdmin, error: adminError } = await userClient.rpc("is_platform_admin");
      authorized = !adminError && isAdmin === true;
    }
  } else if (cronSecret) {
    const { data: isCron, error: cronError } = await userClient.rpc("is_notification_cron_secret", { p_secret: cronSecret });
    authorized = !cronError && isCron === true;
  }
  if (!authorized) return json({ error: "ADMIN_OR_CRON_AUTH_REQUIRED" }, 403);

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("EMAIL_FROM");
  if (!serviceRoleKey || !resendKey || !from) {
    return json({ error: "EMAIL_PROVIDER_NOT_CONFIGURED", required_settings: ["SUPABASE_SERVICE_ROLE_KEY", "RESEND_API_KEY", "EMAIL_FROM"] }, 503);
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: queue, error: queueError } = await adminClient
    .from("platform_notifications")
    .select("id,recipient_user_id,title,body,action_url,email_attempts")
    .eq("email_status", "queued")
    .order("created_at", { ascending: true })
    .limit(50);
  if (queueError) return json({ error: "QUEUE_READ_FAILED" }, 500);

  let sent = 0, failed = 0;
  for (const item of queue || []) {
    const { data: recipient } = await adminClient.auth.admin.getUserById(item.recipient_user_id);
    const email = recipient.user?.email;
    const { data: preferences } = await adminClient
      .from("platform_notification_preferences")
      .select("email_enabled")
      .eq("user_id", item.recipient_user_id)
      .maybeSingle();
    if (preferences?.email_enabled !== true) {
      await adminClient.from("platform_notifications").update({
        email_status: "not_requested", email_requested: false, email_error: null,
      }).eq("id", item.id);
      continue;
    }
    if (!email) {
      await adminClient.from("platform_notifications").update({
        email_status: "failed", email_attempts: (item.email_attempts || 0) + 1,
        email_error: "RECIPIENT_EMAIL_MISSING",
      }).eq("id", item.id);
      failed++;
      continue;
    }
    const baseUrl = Deno.env.get("SITE_URL") || "https://shahadatyofficial.github.io/shahadaty/";
    const actionUrl = item.action_url ? new URL(item.action_url, baseUrl).toString() : baseUrl;
    const html = `<div dir="rtl" style="font-family:Arial,sans-serif;line-height:1.9;color:#17334f;max-width:620px;margin:auto"><h2>${escapeHtml(item.title)}</h2><p>${escapeHtml(item.body || "")}</p><p><a href="${escapeHtml(actionUrl)}" style="display:inline-block;background:#075985;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none">فتح منصة شهادتي</a></p><hr><small>شهادتي العلمية · نصنع المعرفة... نبني الحاضر... ونوثق المستقبل.</small></div>`;
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from, to: [email], subject: item.title, html }),
      signal: AbortSignal.timeout(15000),
    }).catch(() => null);
    if (response?.ok) {
      await adminClient.from("platform_notifications").update({
        email_status: "sent", email_sent_at: new Date().toISOString(),
        email_attempts: (item.email_attempts || 0) + 1, email_error: null,
      }).eq("id", item.id);
      sent++;
    } else {
      const providerMessage = response ? (await response.text().catch(() => "")).slice(0, 400) : "EMAIL_PROVIDER_UNAVAILABLE";
      await adminClient.from("platform_notifications").update({
        email_status: "failed", email_attempts: (item.email_attempts || 0) + 1,
        email_error: providerMessage,
      }).eq("id", item.id);
      failed++;
    }
  }
  return json({ processed: (queue || []).length, sent, failed });
});
