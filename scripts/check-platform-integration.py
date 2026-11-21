from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "admin.html": [
        "runAdminAiInsights", "admin_insights", "platform_notifications", "send-platform-notification-emails",
        "admin_list_institutions", "admin_list_subscriptions",
        "admin_confirm_subscription_payment", "loadSupportInbox",
        "loadGraduateConsentAudit", "uploadAlumniDocument",
    ],
    "institution.html": [
        "institution_submit_subscription_payment_reference", "loadQuotaDetails",
        "admin", "subscriptionPaymentReference",
        "institutionWorkspaceChooser", "openCertificateDashboard",
        "openInstitutionProgram", "workspace-choice-card",
        "staff.shahadaty.invalid", "staffPasswordChangeScreen",
        "complete_institution_staff_password_change", "workspaceSb.auth.signInWithPassword",
    ],
    "institution-workspace.html": [
        "runPublicListing", "runInstitutionAiInsights", "institution_insights", "platform_notifications", "loadPlatformNotifications", "platform_notification_preferences", "institution_list_training_marketplace_applications",
        "institution_review_training_marketplace_application",
        "institution_branches", "institution_users", "institution-staff-create-account",
        "institution_staff_profiles", "institution_user_permission_overrides",
        "createStaffAccountBtn", "staffPermissionsModal", "editStaffAccountModal",
        "data-edit-staff", "institution-staff-update-account",
        "issue_certificate", "graduate-institution-account-create",
        "operationalReadinessCard", "loadOperationalReadiness",
        "operationalReadinessStats", "operationalReadinessSteps",
    ],
    "graduate-v2.html": [
        "graduate_publication_consents", "graduate-publication-consent-sync",
        "graduate-gold-private", "graduate_withdraw_job_application",
        "graduate_my_certificates", "get_public_professional_profile",
        "refreshPublicProfileShare", "public_profile_consent", "platform_notifications", "loadPlatformNotifications",
        "graduate_list_my_training_applications", "digital_passport_public_consent", "digitalPassportConsent", "refreshDigitalPassportShare", "digital-passport.html",
    ],
    "training-marketplace.html": [
        "get_public_training_marketplace", "submit_training_marketplace_application", "contactConsent",
    ],
    "digital-passport.html": [
        "get_public_digital_passport", "QRCode", "verify.html?cert=",
    ],
    "professional-profile.html": [
        "get_public_professional_profile", "qualifications", "skills", "experiences",
    ],
    "supabase/functions/send-platform-notification-emails/index.ts": [
        "EMAIL_PROVIDER_NOT_CONFIGURED", "platform_notifications", "x-cron-secret",
    ],
    "supabase/functions/shahadaty-ai-assistant/index.ts": [
        "get_admin_ai_insights_context", "admin_insights", "get_institution_ai_insights_context", "institution_insights",
    ],
    "supabase/migrations/20261121110000_training_marketplace.sql": [
        "institution_review_training_marketplace_application", "COURSE_CAPACITY_REACHED", "v_enrolled",
    ],
    "supabase/migrations/20261121130000_platform_notifications.sql": [
        "notify_graduate_certificate_event", "training_session_created", "certificate_status_update",
    ],
    "supabase/migrations/20261121140000_notification_scheduling.sql": [
        "enqueue_due_platform_reminders", "graduate-session", "shahadaty_notification_email_delivery",
    ],
    "supabase/migrations/20261121170000_institution_ai_insights.sql": [
        "get_institution_ai_insights_context", "reports.view", "past_sessions_without_attendance",
    ],
    "company.html": [
        "platform_notifications", "loadCompanyPlatformNotifications", "companyEmailNotifications", "search_alumni_for_company_v3", "public_profile_available", "digital_passport_available", "digital-passport.html",
        "search_alumni_for_company", "alumni_access_requests",
        "company_get_approved_alumni_contact", "alumni_documents",
        "company_list_job_applications",
    ],
}

migration_paths = [
    "supabase/migrations/202611140001_graduate_gold_private_uploads.sql",
    "supabase/migrations/202611140006_enforce_publication_consent_for_employer_access.sql",
    "supabase/migrations/202611150001_institution_multi_branch_workspace.sql",
    "supabase/migrations/202611150002_institution_team_roles.sql",
    "supabase/migrations/202611190001_graduate_institution_auto_accounts.sql",
    "supabase/migrations/202611190003_institution_training_operations_hardening.sql",
    "supabase/migrations/202611190004_company_application_review_workflow.sql",
    "supabase/migrations/202611210001_hide_expired_jobs_from_graduates.sql",
    "supabase/migrations/202611210002_atomic_employment_request_admin_updates.sql",
    "supabase/migrations/202611210003_graduate_job_application_withdrawal.sql",
    "supabase/migrations/20261121100000_public_professional_profile_share.sql",
    "supabase/migrations/20261121110000_training_marketplace.sql",
    "supabase/migrations/20261121120000_admin_ai_insights.sql",
    "supabase/migrations/20261121130000_platform_notifications.sql",
    "supabase/migrations/20261121140000_notification_scheduling.sql",
    "supabase/migrations/20261121150000_company_professional_profile_link.sql",
    "supabase/migrations/20261121160000_digital_passport.sql",
    "supabase/migrations/20261121170000_institution_ai_insights.sql",
    "supabase/config.toml",
]

failed = False
for page, required in checks.items():
    path = ROOT / page
    if not path.exists():
        print(f"FAIL missing platform route: {page}")
        failed = True
        continue
    source = path.read_text(encoding="utf-8")
    missing = [item for item in required if item not in source]
    if missing:
        print(f"FAIL {page}: missing integration points: {', '.join(missing)}")
        failed = True
    else:
        print(f"PASS {page}: {len(required)} integration points")

for item in migration_paths:
    if not (ROOT / item).is_file():
        print(f"FAIL missing applied-feature migration in repository: {item}")
        failed = True
    else:
        print(f"PASS migration tracked: {Path(item).name}")

# Public browser pages must never contain privileged Supabase server keys.
public_pages = [ROOT / page for page in [
    "index.html", "admin.html", "institution.html", "institution-workspace.html",
    "graduate-v2.html", "professional-profile.html", "training-marketplace.html", "company.html", "register.html",
]]
for path in public_pages:
    source = path.read_text(encoding="utf-8")
    forbidden = ["SUPABASE_SERVICE_ROLE_KEY", "service_role_secret", "sb_secret_"]
    found = [token for token in forbidden if token in source]
    if found:
        print(f"FAIL privileged key marker found in browser page: {path.name}")
        failed = True
    else:
        print(f"PASS no privileged key marker: {path.name}")

if failed:
    sys.exit(1)
print("All platform integration regression checks passed. No production or synthetic records were created.")
