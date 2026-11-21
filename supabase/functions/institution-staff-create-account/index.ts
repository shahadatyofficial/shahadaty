import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set([
  "https://shahadatyofficial.github.io",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);
const headers = (origin: string) => ({
  "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://shahadatyofficial.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const reply = (origin: string, status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...headers(origin), "Content-Type": "application/json; charset=utf-8" } });

const permissionKeys = [
  "dashboard.view","branches.view","branches.manage","team.view","team.manage",
  "trainees.view","trainees.manage","courses.view","courses.manage",
  "certificates.view","certificates.issue","certificates.revoke","reports.view",
];
const roles = ["training_manager","registrar","certificate_issuer","branch_manager","viewer"];

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  if (req.method === "OPTIONS") {
    if (origin && !allowedOrigins.has(origin)) return new Response("Forbidden", { status: 403 });
    return new Response("ok", { headers: headers(origin) });
  }
  if (req.method !== "POST") return reply(origin, 405, { error: "METHOD_NOT_ALLOWED" });
  if (origin && !allowedOrigins.has(origin)) return reply(origin, 403, { error: "FORBIDDEN" });

  const url = Deno.env.get("SUPABASE_URL") || "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || "";
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY") || "";
  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!url || !anon || !secret || !token) return reply(origin, 401, { error: "UNAUTHORIZED" });

  let createdUserId: string | null = null;
  let createdMembershipId: string | null = null;
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    const caller = createClient(url, anon, {
      global: { headers: { Authorization: "Bearer " + token } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    if (authError || !authData.user) return reply(origin, 401, { error: "UNAUTHORIZED" });

    const raw = await req.text();
    if (raw.length > 12000) return reply(origin, 400, { error: "INVALID_REQUEST" });
    let body: any;
    try { body = JSON.parse(raw); } catch { return reply(origin, 400, { error: "INVALID_JSON" }); }

    const institutionId = String(body?.institution_id || "").trim();
    const username = String(body?.username || "").trim().toLowerCase();
    const fullName = String(body?.full_name || "").trim();
    const password = String(body?.password || "");
    const role = String(body?.role || "").trim();
    const phone = String(body?.phone || "").trim() || null;
    const contactEmail = String(body?.contact_email || "").trim().toLowerCase() || null;
    const jobTitle = String(body?.job_title || "").trim() || null;
    const startDate = body?.employment_start_date ? String(body.employment_start_date) : null;
    const branchIds = Array.isArray(body?.branch_ids)
      ? Array.from(new Set((body.branch_ids as unknown[]).map((x: unknown) => String(x).trim()).filter(Boolean))) as string[]
      : [];
    const permissions = Array.isArray(body?.permissions)
      ? Array.from(new Set((body.permissions as unknown[]).map((x: unknown) => String(x).trim()).filter(Boolean))) as string[]
      : [];
    if (!/^[0-9a-f-]{36}$/i.test(institutionId) ||
        !/^[a-z][a-z0-9._-]{2,29}$/.test(username) ||
        fullName.length < 2 || fullName.length > 160 ||
        password.length < 10 || password.length > 128 ||
        !roles.includes(role) || branchIds.length > 25 ||
        permissions.some((p: string) => !permissionKeys.includes(p)) ||
        (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(contactEmail)) ||
        (startDate && !/^\d{4}-\d{2}-\d{2}$/.test(startDate))) {
      return reply(origin, 400, { error: "INVALID_REQUEST" });
    }
    if (role !== "manager" && branchIds.length === 0) return reply(origin, 400, { error: "BRANCH_ASSIGNMENT_REQUIRED" });

    const { data: permitted, error: permissionError } = await caller.rpc("institution_has_permission", {
      p_institution_id: institutionId, p_permission: "team.manage", p_branch_id: null,
    });
    if (permissionError || permitted !== true) return reply(origin, 403, { error: "TEAM_MANAGEMENT_FORBIDDEN" });

    const { data: institution, error: institutionError } = await admin
      .from("institutions").select("id,status").eq("id", institutionId).maybeSingle();
    if (institutionError || !institution || institution.status !== "approved") {
      return reply(origin, 404, { error: "INSTITUTION_NOT_ACTIVE" });
    }
    if (branchIds.length) {
      const { data: validBranches, error: branchError } = await admin.from("institution_branches")
        .select("id").eq("institution_id", institutionId).eq("is_active", true).in("id", branchIds);
      if (branchError || (validBranches || []).length !== branchIds.length) return reply(origin, 400, { error: "INVALID_BRANCH_ASSIGNMENT" });
    }
    const { data: duplicate } = await admin.from("institution_staff_profiles").select("id")
      .eq("username", username).limit(1).maybeSingle();
    if (duplicate) return reply(origin, 409, { error: "USERNAME_ALREADY_EXISTS" });

    const syntheticEmail = username + "@staff.shahadaty.invalid";
    const { data: authCreated, error: authCreateError } = await admin.auth.admin.createUser({
      email: syntheticEmail, password, email_confirm: true,
    });
    if (authCreateError || !authCreated?.user) return reply(origin, 409, { error: "ACCOUNT_CREATE_FAILED" });
    createdUserId = authCreated.user.id;

    const { data: membership, error: membershipError } = await admin.from("institution_users")
      .insert({ institution_id: institutionId, auth_user_id: createdUserId, role, status: "active" })
      .select("id").single();
    if (membershipError || !membership) throw new Error("MEMBERSHIP_CREATE_FAILED");
    createdMembershipId = membership.id;

    if (branchIds.length) {
      const { error } = await admin.from("institution_user_branches").insert(
        branchIds.map((branch_id: string) => ({ institution_user_id: createdMembershipId, branch_id })),
      );
      if (error) throw new Error("BRANCH_ASSIGNMENT_FAILED");
    }
    const { error: profileError } = await admin.from("institution_staff_profiles").insert({
      institution_id: institutionId, institution_user_id: createdMembershipId, auth_user_id: createdUserId,
      username, full_name: fullName, phone, contact_email: contactEmail, job_title: jobTitle,
      employment_start_date: startDate, created_by: authData.user.id,
    });
    if (profileError) throw new Error("STAFF_PROFILE_CREATE_FAILED");

    if (Array.isArray(body?.permissions)) {
      const overrides = permissionKeys.map((permission_key: string) => ({
        institution_id: institutionId, institution_user_id: createdMembershipId,
        permission_key, is_granted: permissions.includes(permission_key),
      }));
      const { error } = await admin.from("institution_user_permission_overrides").insert(overrides);
      if (error) throw new Error("PERMISSION_OVERRIDES_CREATE_FAILED");
    }

    await admin.auth.admin.updateUserById(createdUserId, {
      app_metadata: { account_type: "institution_staff", institution_id: institutionId, must_change_password: true },
    });
    return reply(origin, 200, { success: true, username, role, membership_status: "active" });
  } catch (error: unknown) {
    if (createdMembershipId) {
      await admin.from("institution_user_permission_overrides").delete().eq("institution_user_id", createdMembershipId);
      await admin.from("institution_staff_profiles").delete().eq("institution_user_id", createdMembershipId);
      await admin.from("institution_user_branches").delete().eq("institution_user_id", createdMembershipId);
      await admin.from("institution_users").delete().eq("id", createdMembershipId);
    }
    if (createdUserId) await admin.auth.admin.deleteUser(createdUserId);
    const message = error instanceof Error ? error.message : "INTERNAL_ERROR";
    console.error("institution-staff-create-account:", message);
    return reply(origin, 500, { error: message });
  }
});
