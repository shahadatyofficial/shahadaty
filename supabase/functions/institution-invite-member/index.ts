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
  new Response(JSON.stringify(body), {
    status,
    headers: { ...headers(origin), "Content-Type": "application/json; charset=utf-8" },
  });

async function findUserByEmail(admin: any, email: string) {
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = data?.users || [];
    const found = users.find((u: any) => String(u.email || "").toLowerCase() === email);
    if (found) return found;
    if (users.length < 1000) return null;
  }
  throw new Error("USER_LOOKUP_LIMIT");
}

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

  try {
    const caller = createClient(url, anon, {
      global: { headers: { Authorization: "Bearer " + token } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await caller.auth.getUser(token);
    if (authError || !authData.user) return reply(origin, 401, { error: "UNAUTHORIZED" });

    const raw = await req.text();
    if (raw.length > 8000) return reply(origin, 400, { error: "INVALID_REQUEST" });
    let body: any;
    try { body = JSON.parse(raw); } catch { return reply(origin, 400, { error: "INVALID_JSON" }); }

    const institutionId = String(body?.institution_id || "").trim();
    const email = String(body?.email || "").trim().toLowerCase();
    const role = String(body?.role || "").trim();
    const branchIds: string[] = Array.isArray(body?.branch_ids)
      ? [...new Set((body.branch_ids as unknown[]).map((x: unknown): string => String(x).trim()).filter((x: string): boolean => x.length > 0))]
      : [];
    if (!/^[0-9a-f-]{36}$/i.test(institutionId) ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) ||
        !["manager", "training_manager", "registrar", "certificate_issuer", "branch_manager", "viewer"].includes(role) ||
        branchIds.length > 25) {
      return reply(origin, 400, { error: "INVALID_REQUEST" });
    }
    if (role !== "manager" && branchIds.length === 0) {
      return reply(origin, 400, { error: "BRANCH_ASSIGNMENT_REQUIRED" });
    }

    const { data: permitted, error: permissionError } = await caller.rpc("institution_has_permission", {
      p_institution_id: institutionId,
      p_permission: "team.manage",
      p_branch_id: null,
    });
    if (permissionError || permitted !== true) return reply(origin, 403, { error: "TEAM_MANAGEMENT_FORBIDDEN" });

    const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: institution, error: institutionError } = await admin
      .from("institutions").select("id,status,name").eq("id", institutionId).maybeSingle();
    if (institutionError || !institution || institution.status !== "approved") {
      return reply(origin, 404, { error: "INSTITUTION_NOT_ACTIVE" });
    }

    if (branchIds.length) {
      const { data: validBranches, error: branchError } = await admin
        .from("institution_branches").select("id").eq("institution_id", institutionId)
        .eq("is_active", true).in("id", branchIds);
      if (branchError || (validBranches || []).length !== branchIds.length) {
        return reply(origin, 400, { error: "INVALID_BRANCH_ASSIGNMENT" });
      }
    }

    const target = await findUserByEmail(admin, email);
    if (target && !target.email_confirmed_at) {
      return reply(origin, 409, { error: "ACCOUNT_EMAIL_NOT_CONFIRMED" });
    }
    let priorMembership: any = null;
    if (target) {
      const { data, error } = await admin.from("institution_users").select("id,role,status")
        .eq("institution_id", institutionId).eq("auth_user_id", target.id).maybeSingle();
      if (error) return reply(origin, 500, { error: "MEMBERSHIP_CHECK_FAILED" });
      priorMembership = data;
    }
    if (priorMembership?.status === "active") return reply(origin, 409, { error: "ALREADY_A_MEMBER" });
    if (priorMembership?.role === "owner") return reply(origin, 409, { error: "OWNER_MEMBERSHIP_PROTECTED" });

    const { data: hasCapacity, error: capacityError } = await caller.rpc("institution_feature_has_capacity", {
      p_institution_id: institutionId,
      p_feature: "staff",
    });
    if (capacityError || hasCapacity !== true) return reply(origin, 409, { error: "STAFF_LIMIT_REACHED" });

    let invitedUser = target;
    let invitationEmailSent = false;
    if (!invitedUser) {
      const redirectTo = "https://shahadatyofficial.github.io/shahadaty/institution.html";
      const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
      if (error || !data?.user) return reply(origin, 502, { error: "INVITATION_EMAIL_FAILED" });
      invitedUser = data.user;
      invitationEmailSent = true;
    }

    const { data: previousAssignments, error: previousAssignmentsError } = priorMembership
      ? await admin.from("institution_user_branches").select("branch_id").eq("institution_user_id", priorMembership.id)
      : { data: [], error: null };
    if (previousAssignmentsError) return reply(origin, 500, { error: "BRANCH_ASSIGNMENT_LOOKUP_FAILED" });

    let membershipId = priorMembership?.id;
    if (priorMembership) {
      const { error } = await admin.from("institution_users")
        .update({ role, status: "active" }).eq("id", membershipId);
      if (error) return reply(origin, 500, { error: "MEMBERSHIP_ACTIVATION_FAILED" });
    } else {
      const { data, error } = await admin.from("institution_users")
        .insert({ institution_id: institutionId, auth_user_id: invitedUser.id, role, status: "active" })
        .select("id").single();
      if (error || !data) return reply(origin, 500, { error: "MEMBERSHIP_CREATE_FAILED" });
      membershipId = data.id;
    }

    if (priorMembership) {
      await admin.from("institution_user_branches").delete().eq("institution_user_id", membershipId);
    }
    if (branchIds.length) {
      const { error } = await admin.from("institution_user_branches")
        .insert(branchIds.map((branch_id: string) => ({ institution_user_id: membershipId, branch_id })));
      if (error) {
        if (priorMembership) {
          await admin.from("institution_users").update({ role: priorMembership.role, status: priorMembership.status }).eq("id", membershipId);
          if (previousAssignments?.length) await admin.from("institution_user_branches").insert(
            previousAssignments.map((x: any) => ({ institution_user_id: membershipId, branch_id: x.branch_id })),
          );
        } else {
          await admin.from("institution_users").delete().eq("id", membershipId);
        }
        return reply(origin, 500, { error: "BRANCH_ASSIGNMENT_FAILED" });
      }
    }

    const invitationPayload = {
      institution_id: institutionId,
      invited_email: email,
      invited_user_id: invitedUser.id,
      role,
      status: invitationEmailSent ? "sent" : "accepted",
      invited_by: authData.user.id,
      accepted_at: invitationEmailSent ? null : new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    const { data: pendingInvitation } = await admin.from("institution_invitations")
      .select("id").eq("institution_id", institutionId).eq("invited_email", email)
      .in("status", ["pending", "sent"]).maybeSingle();
    const invitationWrite = pendingInvitation
      ? await admin.from("institution_invitations").update(invitationPayload).eq("id", pendingInvitation.id)
      : await admin.from("institution_invitations").insert(invitationPayload);
    const invitationError = invitationWrite.error;
    if (invitationError) {
      await admin.from("institution_user_branches").delete().eq("institution_user_id", membershipId);
      if (priorMembership) {
        await admin.from("institution_users").update({ role: priorMembership.role, status: priorMembership.status }).eq("id", membershipId);
        if (previousAssignments?.length) await admin.from("institution_user_branches").insert(
          previousAssignments.map((x: any) => ({ institution_user_id: membershipId, branch_id: x.branch_id })),
        );
      } else {
        await admin.from("institution_users").delete().eq("id", membershipId);
      }
      return reply(origin, 500, { error: "INVITATION_AUDIT_FAILED" });
    }

    return reply(origin, 200, {
      success: true,
      email,
      role,
      invitation_email_sent: invitationEmailSent,
      membership_status: "active",
    });
  } catch (error: unknown) {
    console.error("institution-invite-member:", error instanceof Error ? error.message : error);
    return reply(origin, 500, { error: "INTERNAL_ERROR" });
  }
});
