-- ============================================================
-- منصة شهادتي - قاعدة البيانات الأساسية V2
-- هذه النسخة هي الأساس قبل تطوير بقية البوابة.
-- شغّلها في Supabase SQL Editor بعد أخذ نسخة احتياطية.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- Packages
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.packages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text UNIQUE NOT NULL,
  name_ar text NOT NULL,
  quota integer NOT NULL DEFAULT 0 CHECK (quota >= 0),
  price_monthly numeric(10,2) NOT NULL DEFAULT 0 CHECK (price_monthly >= 0),
  price_yearly numeric(10,2) NOT NULL DEFAULT 0 CHECK (price_yearly >= 0),
  features jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- Institutions
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.institutions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  name_en text,
  logo_url text,
  type text NOT NULL DEFAULT 'أخرى',
  governorate text NOT NULL,
  address text NOT NULL,

  -- بيانات التواصل
  contact_email text UNIQUE NOT NULL,
  contact_phone text NOT NULL,

  -- البيانات القانونية
  commercial_registration text,
  tax_card_number text,
  owner_name text,
  manager_name text,
  license_number text,

  package_id uuid REFERENCES public.packages(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','suspended','rejected')),
  quota_total integer NOT NULL DEFAULT 0 CHECK (quota_total >= 0),
  quota_used integer NOT NULL DEFAULT 0 CHECK (quota_used >= 0 AND quota_used <= quota_total),
  subscription_start timestamptz,
  subscription_end timestamptz,

  policy_accepted boolean NOT NULL DEFAULT false,
  policy_accepted_at timestamptz,
  data_accuracy_accepted boolean NOT NULL DEFAULT false,
  data_accuracy_accepted_at timestamptz,

  approved_at timestamptz,
  approved_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  rejection_reason text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS institutions_status_idx ON public.institutions(status);
CREATE INDEX IF NOT EXISTS institutions_package_idx ON public.institutions(package_id);
CREATE INDEX IF NOT EXISTS institutions_auth_user_idx ON public.institutions(auth_user_id);

-- ------------------------------------------------------------
-- Institution users / roles
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.institution_users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'owner' CHECK (role IN ('owner','admin','staff','viewer')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(institution_id, auth_user_id)
);

CREATE INDEX IF NOT EXISTS institution_users_auth_idx ON public.institution_users(auth_user_id);

-- ------------------------------------------------------------
-- Accreditation requests
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.accreditation_requests (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  institution_id uuid UNIQUE REFERENCES public.institutions(id) ON DELETE SET NULL,

  institution_name text NOT NULL,
  institution_type text NOT NULL,
  governorate text NOT NULL,
  address text NOT NULL,
  contact_email text NOT NULL,
  contact_name text NOT NULL,
  contact_phone text NOT NULL,

  commercial_registration text NOT NULL,
  tax_card_number text NOT NULL,
  owner_name text NOT NULL,
  manager_name text NOT NULL,

  package_requested uuid REFERENCES public.packages(id) ON DELETE SET NULL,
  policy_accepted boolean NOT NULL DEFAULT false,
  data_accuracy_accepted boolean NOT NULL DEFAULT false,

  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','reviewing','approved','rejected','needs_update')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  admin_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS accreditation_status_idx ON public.accreditation_requests(status);
CREATE INDEX IF NOT EXISTS accreditation_email_idx ON public.accreditation_requests(contact_email);

-- ------------------------------------------------------------
-- Legal documents
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.institution_documents (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  document_type text NOT NULL CHECK (document_type IN ('commercial_registration','tax_card','institution_proof','other')),
  file_name text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  mime_type text,
  file_size bigint,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS institution_documents_inst_idx ON public.institution_documents(institution_id);

-- ------------------------------------------------------------
-- Subscriptions
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  package_id uuid NOT NULL REFERENCES public.packages(id),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','expired','cancelled','suspended')),
  billing_cycle text NOT NULL DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly','yearly')),
  amount numeric(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  start_at timestamptz,
  end_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS subscriptions_inst_idx ON public.subscriptions(institution_id);
DO $$ BEGIN
  UPDATE public.subscriptions s SET status='cancelled', updated_at=now()
  WHERE s.status='active' AND s.id NOT IN (
    SELECT DISTINCT ON (institution_id) id FROM public.subscriptions WHERE status='active' ORDER BY institution_id,created_at DESC
  );
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_one_active_idx ON public.subscriptions(institution_id) WHERE status='active';

-- ------------------------------------------------------------
-- Certificates
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.certificates (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  cert_number text UNIQUE NOT NULL,
  student_name text NOT NULL,
  student_name_en text,
  student_national_id text,
  student_phone text,
  course text NOT NULL,
  specialization text,
  issue_date date NOT NULL,
  expiry_date date,
  grade text,
  grade_value numeric(5,2),
  duration text,
  governorate text,
  pdf_url text,
  qr_code text,
  visible_to_companies boolean NOT NULL DEFAULT false,
  consent_given_at timestamptz,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','expired')),
  added_by text NOT NULL DEFAULT 'institution' CHECK (added_by IN ('institution','admin')),
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS certificates_institution_idx ON public.certificates(institution_id);
CREATE INDEX IF NOT EXISTS certificates_status_idx ON public.certificates(status);
CREATE INDEX IF NOT EXISTS certificates_number_idx ON public.certificates(cert_number);

-- ------------------------------------------------------------
-- Verification log
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.certificate_verifications (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  certificate_id uuid REFERENCES public.certificates(id) ON DELETE SET NULL,
  cert_number text NOT NULL,
  verifier_type text NOT NULL DEFAULT 'public' CHECK (verifier_type IN ('public','institution','company','admin')),
  verifier_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS verification_number_idx ON public.certificate_verifications(cert_number);

-- ------------------------------------------------------------
-- Companies / recruitment
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.companies (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  company_name text NOT NULL,
  contact_name text,
  contact_email text UNIQUE NOT NULL,
  contact_phone text,
  industry text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','suspended')),
  subscription_tier text NOT NULL DEFAULT 'free',
  search_credits integer NOT NULL DEFAULT 10 CHECK (search_credits >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.recruitment_requests (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_name text NOT NULL,
  contact_name text NOT NULL,
  contact_email text NOT NULL,
  contact_phone text,
  qualification text NOT NULL,
  governorate text,
  graduation_year text,
  positions_needed integer NOT NULL DEFAULT 1 CHECK (positions_needed > 0),
  message text,
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','processing','fulfilled','closed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- Activity log / settings
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activity_log (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id uuid,
  actor_type text,
  action text NOT NULL,
  target_type text,
  target_id uuid,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.system_settings (
  key text PRIMARY KEY,
  value text,
  description text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- Repair existing installations: add fields introduced in V2.
-- CREATE TABLE IF NOT EXISTS does not alter an existing table, so
-- these ALTER statements make the migration safe for the current project.
-- ------------------------------------------------------------
ALTER TABLE public.packages ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS commercial_registration text;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS tax_card_number text;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS owner_name text;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS manager_name text;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS data_accuracy_accepted boolean NOT NULL DEFAULT false;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS data_accuracy_accepted_at timestamptz;
ALTER TABLE public.institutions ADD COLUMN IF NOT EXISTS rejection_reason text;

ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS institution_id uuid REFERENCES public.institutions(id) ON DELETE SET NULL;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS contact_name text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS institution_type text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS commercial_registration text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS tax_card_number text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS owner_name text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS manager_name text;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS data_accuracy_accepted boolean NOT NULL DEFAULT false;
ALTER TABLE public.accreditation_requests ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS visible_to_companies boolean NOT NULL DEFAULT false;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS student_phone text;
ALTER TABLE public.certificates ADD COLUMN IF NOT EXISTS consent_given_at timestamptz;

-- ------------------------------------------------------------
-- Triggers
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS institutions_updated_at ON public.institutions;
CREATE TRIGGER institutions_updated_at BEFORE UPDATE ON public.institutions
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS accreditation_updated_at ON public.accreditation_requests;
CREATE TRIGGER accreditation_updated_at BEFORE UPDATE ON public.accreditation_requests
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS packages_updated_at ON public.packages;
CREATE TRIGGER packages_updated_at BEFORE UPDATE ON public.packages
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

DROP TRIGGER IF EXISTS subscriptions_updated_at ON public.subscriptions;
CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ------------------------------------------------------------
-- Secure certificate numbering
-- ------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.certificate_number_seq START 1;

CREATE OR REPLACE FUNCTION public.generate_cert_number()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  prefix text;
BEGIN
  SELECT COALESCE(value, 'SHD') INTO prefix
  FROM public.system_settings WHERE key = 'cert_prefix';
  RETURN prefix || '-' || TO_CHAR(now(), 'YYYY') || '-' || LPAD(nextval('public.certificate_number_seq')::text, 7, '0');
END;
$$;

-- ------------------------------------------------------------
-- Registration -> Auth user -> Institution
-- The browser only creates an accreditation request.
-- The auth trigger creates the institution server-side.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_institution_from_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req public.accreditation_requests%ROWTYPE;
  new_inst_id uuid;
  pkg_quota integer := 0;
BEGIN
  IF NEW.raw_user_meta_data ? 'registration_request_id' THEN
    SELECT * INTO req
    FROM public.accreditation_requests
    WHERE id = (NEW.raw_user_meta_data ->> 'registration_request_id')::uuid
    LIMIT 1;

    IF req.id IS NOT NULL AND req.auth_user_id IS NULL THEN
      IF req.package_requested IS NOT NULL THEN
        SELECT quota INTO pkg_quota FROM public.packages WHERE id = req.package_requested;
      END IF;

      INSERT INTO public.institutions (
        auth_user_id, name, type, governorate, address,
        contact_email, contact_phone,
        commercial_registration, tax_card_number, owner_name, manager_name,
        package_id, status, quota_total, quota_used,
        policy_accepted, policy_accepted_at,
        data_accuracy_accepted, data_accuracy_accepted_at
      ) VALUES (
        NEW.id, req.institution_name, req.institution_type, req.governorate, req.address,
        req.contact_email, req.contact_phone,
        req.commercial_registration, req.tax_card_number, req.owner_name, req.manager_name,
        req.package_requested, 'pending', COALESCE(pkg_quota,0), 0,
        req.policy_accepted, CASE WHEN req.policy_accepted THEN now() ELSE NULL END,
        req.data_accuracy_accepted, CASE WHEN req.data_accuracy_accepted THEN now() ELSE NULL END
      ) RETURNING id INTO new_inst_id;

      INSERT INTO public.institution_users (institution_id, auth_user_id, role)
      VALUES (new_inst_id, NEW.id, 'owner');

      UPDATE public.accreditation_requests
      SET auth_user_id = NEW.id,
          institution_id = new_inst_id,
          status = 'new',
          updated_at = now()
      WHERE id = req.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_registration ON auth.users;
CREATE TRIGGER on_auth_user_registration
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.create_institution_from_registration();

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------
ALTER TABLE public.packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institution_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accreditation_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.institution_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.certificates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.certificate_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recruitment_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;

-- Drop old policies where names are known, so this file can repair an existing DB.
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT schemaname, tablename, policyname
           FROM pg_policies
           WHERE schemaname='public'
             AND tablename IN ('packages','institutions','institution_users','accreditation_requests','institution_documents','subscriptions','certificates','certificate_verifications','companies','recruitment_requests','activity_log','system_settings')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
  END LOOP;
END $$;

-- Public can only read active package catalog.
CREATE POLICY packages_public_read ON public.packages
FOR SELECT USING (is_active = true);

-- Registration request: public can create a pending request, never read it back.
CREATE POLICY accreditation_public_insert ON public.accreditation_requests
FOR INSERT WITH CHECK (
  status = 'new'
  AND policy_accepted = true
  AND data_accuracy_accepted = true
);
CREATE POLICY accreditation_admin_all ON public.accreditation_requests
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Institutions.
CREATE POLICY institutions_self_read ON public.institutions
FOR SELECT USING (auth.uid() = auth_user_id OR public.is_admin());
CREATE POLICY institutions_self_update ON public.institutions
FOR UPDATE USING (public.is_admin())
WITH CHECK (public.is_admin());
CREATE POLICY institutions_admin_insert ON public.institutions
FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY institutions_admin_all ON public.institutions
FOR DELETE USING (public.is_admin());

-- Institution membership.
CREATE POLICY institution_users_self_read ON public.institution_users
FOR SELECT USING (auth.uid() = auth_user_id OR public.is_admin());
CREATE POLICY institution_users_admin_all ON public.institution_users
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Documents: private to owning institution and admins.
CREATE POLICY institution_documents_owner_read ON public.institution_documents
FOR SELECT USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = institution_documents.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
);
CREATE POLICY institution_documents_owner_insert ON public.institution_documents
FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = institution_documents.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
);
CREATE POLICY institution_documents_admin_update ON public.institution_documents
FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY institution_documents_admin_delete ON public.institution_documents
FOR DELETE USING (public.is_admin());

-- Subscriptions.
CREATE POLICY subscriptions_owner_read ON public.subscriptions
FOR SELECT USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = subscriptions.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
);
CREATE POLICY subscriptions_admin_all ON public.subscriptions
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Certificates: no public SELECT on the raw table.
-- Public verification uses the safe RPC below so national ID/phone and other private
-- columns are never exposed by a table-wide anonymous SELECT.
CREATE POLICY certificates_owner_read ON public.certificates
FOR SELECT USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = certificates.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
);
CREATE POLICY certificates_owner_insert ON public.certificates
FOR INSERT WITH CHECK (false);
CREATE OR REPLACE FUNCTION public.verify_certificate(p_cert_number text)
RETURNS TABLE (
  cert_number text,
  student_name text,
  course text,
  specialization text,
  issue_date date,
  expiry_date date,
  grade text,
  duration text,
  institution_name text,
  institution_type text,
  institution_governorate text,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.certificate_verifications(cert_number, verifier_type)
  SELECT c.cert_number, 'public'
  FROM public.certificates c
  WHERE c.cert_number = trim(p_cert_number)
  LIMIT 1;

  RETURN QUERY
  SELECT c.cert_number, c.student_name, c.course, c.specialization, c.issue_date,
         c.expiry_date, c.grade, c.duration, i.name, i.type, i.governorate, c.status
  FROM public.certificates c
  JOIN public.institutions i ON i.id = c.institution_id
  WHERE c.cert_number = trim(p_cert_number)
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_certificate(text) TO anon, authenticated;

CREATE POLICY certificates_owner_update ON public.certificates
FOR UPDATE USING (
  public.is_admin() OR EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = certificates.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
) WITH CHECK (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.institution_users iu
    WHERE iu.institution_id = certificates.institution_id
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
));

CREATE POLICY certificates_company_search ON public.certificates
FOR SELECT USING (
  visible_to_companies = true
  AND EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.auth_user_id = auth.uid()
      AND c.status = 'approved'
  )
);

-- Verification log: public can record a verification, nobody can read it except admin.
CREATE POLICY verification_public_insert ON public.certificate_verifications
FOR INSERT WITH CHECK (true);
CREATE POLICY verification_admin_read ON public.certificate_verifications
FOR SELECT USING (public.is_admin());

-- Companies.
CREATE POLICY companies_self_read ON public.companies
FOR SELECT USING (auth.uid() = auth_user_id OR public.is_admin());
CREATE POLICY companies_admin_all ON public.companies
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Recruitment requests.
CREATE POLICY recruitment_public_insert ON public.recruitment_requests
FOR INSERT WITH CHECK (true);
CREATE POLICY recruitment_admin_all ON public.recruitment_requests
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Activity log / settings are admin-only.
CREATE POLICY activity_admin_all ON public.activity_log
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY settings_public_read ON public.system_settings
FOR SELECT USING (true);
CREATE POLICY settings_admin_all ON public.system_settings
FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ------------------------------------------------------------
-- Seed packages: source of truth for register.html and packages.html
-- ------------------------------------------------------------
INSERT INTO public.packages (name,name_ar,quota,price_monthly,price_yearly,features,sort_order,is_active)
VALUES
('trial','تجريبية',10,0,0,'["تحقق رقمي","QR Code"]',0,true),
('basic','أساسية',100,125,1499,'["QR لكل شهادة","لوحة تحكم"]',1,true),
('bronze','برونزية',500,333,3999,'["رفع Excel","3 مستخدمين","دعم أولوية"]',2,true),
('silver','فضية',2000,667,7999,'["10 مستخدمين","تقارير متقدمة"]',3,true),
('gold','ذهبية',6000,1249,14999,'["API كامل","دعم VIP"]',4,true),
('enterprise','مؤسسات',0,0,0,'["SLA مضمون","مدير حساب خاص"]',5,true)
ON CONFLICT (name) DO UPDATE SET
  name_ar=EXCLUDED.name_ar,
  quota=EXCLUDED.quota,
  price_monthly=EXCLUDED.price_monthly,
  price_yearly=EXCLUDED.price_yearly,
  features=EXCLUDED.features,
  sort_order=EXCLUDED.sort_order,
  is_active=EXCLUDED.is_active;

INSERT INTO public.system_settings(key,value,description)
VALUES
('platform_name','شهادتي','اسم المنصة'),
('platform_name_en','Shehadaty','اسم المنصة بالإنجليزية'),
('support_email','support@shehadaty.com','بريد الدعم الفني'),
('cert_prefix','SHD','بادئة أرقام الشهادات'),
('maintenance_mode','false','وضع الصيانة')
ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, description=EXCLUDED.description, updated_at=now();

-- ------------------------------------------------------------
-- Storage
-- Create these buckets from Storage if they do not already exist:
--   institution-documents (PRIVATE)
--   certificates (PUBLIC, only if public PDF delivery is desired)
-- ------------------------------------------------------------

-- IMPORTANT: Set an admin user's app_metadata role to "admin" from a trusted server/admin tool.
-- Do NOT put a service_role key in HTML/JavaScript.

-- ------------------------------------------------------------
-- Private legal-document storage
-- ------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('institution-documents', 'institution-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS institution_docs_storage_read ON storage.objects;
CREATE POLICY institution_docs_storage_read ON storage.objects
FOR SELECT USING (
  bucket_id = 'institution-documents'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.institution_users iu
      WHERE iu.institution_id::text = (storage.foldername(name))[1]
        AND iu.auth_user_id = auth.uid()
        AND iu.is_active = true
    )
  )
);

DROP POLICY IF EXISTS institution_docs_storage_insert ON storage.objects;
CREATE POLICY institution_docs_storage_insert ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'institution-documents'
  AND EXISTS (
    SELECT 1
    FROM public.institution_users iu
    WHERE iu.institution_id::text = (storage.foldername(name))[1]
      AND iu.auth_user_id = auth.uid()
      AND iu.is_active = true
  )
);

DROP POLICY IF EXISTS institution_docs_storage_delete ON storage.objects;
CREATE POLICY institution_docs_storage_delete ON storage.objects
FOR DELETE USING (
  bucket_id = 'institution-documents'
  AND (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.institution_users iu
      WHERE iu.institution_id::text = (storage.foldername(name))[1]
        AND iu.auth_user_id = auth.uid()
        AND iu.is_active = true
    )
  )
);

-- ============================================================
-- SHAHADATY V3 FINAL WORKFLOW EXTENSIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id uuid NOT NULL REFERENCES public.institutions(id) ON DELETE CASCADE,
  subscription_id uuid REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  amount numeric(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'EGP',
  provider text,
  provider_reference text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','failed','refunded','cancelled')),
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payments_inst_idx ON public.payments(institution_id);
CREATE INDEX IF NOT EXISTS payments_status_idx ON public.payments(status);
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  institution_id uuid REFERENCES public.institutions(id) ON DELETE CASCADE,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL DEFAULT 'info',
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_user_idx ON public.notifications(auth_user_id, is_read, created_at DESC);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.graduate_profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id uuid UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  email text,
  phone text,
  governorate text,
  bio text,
  profile_public boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.graduate_profiles ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS graduate_profiles_updated_at ON public.graduate_profiles;
CREATE TRIGGER graduate_profiles_updated_at BEFORE UPDATE ON public.graduate_profiles
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE OR REPLACE FUNCTION public.update_my_institution_contact(p_phone text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.institutions SET contact_phone=trim(p_phone),updated_at=now() WHERE auth_user_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
  RETURN true;
END;$$;
GRANT EXECUTE ON FUNCTION public.update_my_institution_contact(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.revoke_my_certificate(p_certificate_id uuid,p_reason text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.certificates c SET status='revoked',revoked_at=now(),revoke_reason=p_reason,updated_at=now()
  WHERE c.id=p_certificate_id AND EXISTS(SELECT 1 FROM public.institution_users iu WHERE iu.institution_id=c.institution_id AND iu.auth_user_id=auth.uid() AND iu.is_active=true AND iu.role IN ('owner','admin'));
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
  INSERT INTO public.activity_log(actor_id,actor_type,action,target_type,target_id,details) VALUES(auth.uid(),'institution','certificate_revoked','certificate',p_certificate_id,jsonb_build_object('reason',p_reason));
  RETURN true;
END;$$;
GRANT EXECUTE ON FUNCTION public.revoke_my_certificate(uuid,text) TO authenticated;

-- Atomic certificate issuing. The browser never generates certificate numbers or quota counters.
CREATE OR REPLACE FUNCTION public.issue_certificate(p_payload jsonb)
RETURNS TABLE(cert_id uuid, cert_number text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  inst_id uuid := (p_payload->>'institution_id')::uuid;
  inst_row public.institutions%ROWTYPE;
  new_id uuid;
  new_number text;
  issue_day date := COALESCE(NULLIF(p_payload->>'issue_date','')::date, CURRENT_DATE);
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT i.* INTO inst_row
  FROM public.institutions i
  JOIN public.institution_users iu ON iu.institution_id=i.id
  WHERE i.id=inst_id AND iu.auth_user_id=uid AND iu.is_active=true
    AND iu.role IN ('owner','admin','staff')
  FOR UPDATE OF i;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
  IF inst_row.status <> 'approved' THEN RAISE EXCEPTION 'INSTITUTION_NOT_APPROVED'; END IF;
  IF inst_row.quota_used >= inst_row.quota_total THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  IF COALESCE(trim(p_payload->>'student_name'),'')='' OR COALESCE(trim(p_payload->>'course'),'')='' THEN
    RAISE EXCEPTION 'REQUIRED_FIELDS';
  END IF;

  new_number := public.generate_cert_number();
  INSERT INTO public.certificates(
    institution_id, cert_number, student_name, student_name_en, student_national_id,
    student_phone, course, specialization, issue_date, expiry_date, grade, grade_value,
    duration, governorate, pdf_url, qr_code, visible_to_companies, consent_given_at,
    status, added_by
  ) VALUES (
    inst_id, new_number, trim(p_payload->>'student_name'), NULLIF(trim(p_payload->>'student_name_en'),''),
    NULLIF(trim(p_payload->>'student_national_id'),''), NULLIF(trim(p_payload->>'student_phone'),''),
    trim(p_payload->>'course'), NULLIF(trim(p_payload->>'specialization'),''), issue_day,
    NULLIF(p_payload->>'expiry_date','')::date, NULLIF(trim(p_payload->>'grade'),''),
    NULLIF(p_payload->>'grade_value','')::numeric, NULLIF(trim(p_payload->>'duration'),''),
    NULLIF(trim(p_payload->>'governorate'),''), NULLIF(trim(p_payload->>'pdf_url'),''),
    NULLIF(trim(p_payload->>'qr_code'),''), COALESCE((p_payload->>'visible_to_companies')::boolean,false),
    CASE WHEN COALESCE((p_payload->>'visible_to_companies')::boolean,false) THEN now() ELSE NULL END,
    'active','institution'
  ) RETURNING id INTO new_id;

  UPDATE public.institutions
  SET quota_used=quota_used+1, updated_at=now()
  WHERE id=inst_id;

  INSERT INTO public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
  VALUES(uid,'institution','certificate_issued','certificate',new_id,jsonb_build_object('cert_number',new_number,'institution_id',inst_id));

  RETURN QUERY SELECT new_id,new_number;
END;
$$;
GRANT EXECUTE ON FUNCTION public.issue_certificate(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.issue_certificates_bulk(p_institution_id uuid, p_rows jsonb)
RETURNS TABLE(success_count integer, failed_count integer, errors jsonb, numbers jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r jsonb; ok integer:=0; bad integer:=0; errs jsonb:='[]'::jsonb; nums jsonb:='[]'::jsonb; result record;
  needed integer:=jsonb_array_length(COALESCE(p_rows,'[]'::jsonb)); current_quota integer; current_used integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.institution_users iu JOIN public.institutions i ON i.id=iu.institution_id
    WHERE iu.institution_id=p_institution_id AND iu.auth_user_id=auth.uid() AND iu.is_active=true
      AND iu.role IN ('owner','admin','staff') AND i.status='approved'
  ) THEN RAISE EXCEPTION 'NOT_ALLOWED'; END IF;
  SELECT quota_total,quota_used INTO current_quota,current_used FROM public.institutions WHERE id=p_institution_id FOR UPDATE;
  IF current_used + needed > current_quota THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows,'[]'::jsonb)) LOOP
    BEGIN
      SELECT * INTO result FROM public.issue_certificate(r || jsonb_build_object('institution_id',p_institution_id));
      ok:=ok+1; nums:=nums || jsonb_build_array(result.cert_number);
    EXCEPTION WHEN OTHERS THEN
      bad:=bad+1; errs:=errs || jsonb_build_array(jsonb_build_object('row',r,'error',SQLERRM));
    END;
  END LOOP;
  RETURN QUERY SELECT ok,bad,errs,nums;
END;
$$;
GRANT EXECUTE ON FUNCTION public.issue_certificates_bulk(uuid,jsonb) TO authenticated;

-- Admin workflow: approve/reject institution and create/update subscription.
CREATE OR REPLACE FUNCTION public.review_institution(p_institution_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE uid uuid:=auth.uid();
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
  IF p_status NOT IN ('approved','rejected','suspended','pending') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  UPDATE public.institutions
  SET status=p_status,
      approved_at=CASE WHEN p_status='approved' THEN now() ELSE approved_at END,
      approved_by=CASE WHEN p_status='approved' THEN uid ELSE approved_by END,
      rejection_reason=CASE WHEN p_status='rejected' THEN p_notes ELSE NULL END,
      notes=COALESCE(p_notes,notes), updated_at=now()
  WHERE id=p_institution_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF p_status='approved' THEN
    INSERT INTO public.subscriptions(institution_id,package_id,status,billing_cycle,amount,start_at,end_at)
    SELECT i.id,i.package_id,'active','monthly',COALESCE(p.price_monthly,0),now(),now()+interval '30 days'
    FROM public.institutions i LEFT JOIN public.packages p ON p.id=i.package_id
    WHERE i.id=p_institution_id
    ON CONFLICT (institution_id) WHERE status='active' DO UPDATE SET package_id=EXCLUDED.package_id, amount=EXCLUDED.amount, start_at=EXCLUDED.start_at, end_at=EXCLUDED.end_at, updated_at=now();
    INSERT INTO public.notifications(institution_id,title,message,type)
    SELECT p_institution_id,'تم اعتماد المؤسسة','تم اعتماد مؤسستك ويمكنك الآن استخدام بوابة المؤسسات.','success';
  ELSIF p_status='rejected' THEN
    INSERT INTO public.notifications(institution_id,title,message,type)
    VALUES(p_institution_id,'تم رفض طلب الاعتماد',COALESCE(p_notes,'يرجى مراجعة الإدارة لمزيد من التفاصيل.'),'error');
  END IF;
  INSERT INTO public.activity_log(actor_id,actor_type,action,target_type,target_id,details)
  VALUES(uid,'admin','institution_reviewed','institution',p_institution_id,jsonb_build_object('status',p_status,'notes',p_notes));
  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.review_institution(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.review_document(p_document_id uuid,p_status text,p_reason text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
  IF p_status NOT IN ('approved','rejected','pending') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
  UPDATE public.institution_documents SET status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason=CASE WHEN p_status='rejected' THEN p_reason ELSE NULL END WHERE id=p_document_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  RETURN true;
END;$$;
GRANT EXECUTE ON FUNCTION public.review_document(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_certificate(p_cert_number text)
RETURNS TABLE(cert_number text,student_name text,course text,specialization text,issue_date date,expiry_date date,grade text,duration text,institution_name text,institution_type text,institution_governorate text,status text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.certificates%ROWTYPE; effective_status text;
BEGIN
  SELECT * INTO c FROM public.certificates WHERE cert_number=upper(trim(p_cert_number)) LIMIT 1;
  IF c.id IS NULL THEN RETURN; END IF;
  effective_status:=CASE WHEN c.status='revoked' THEN 'revoked' WHEN c.expiry_date IS NOT NULL AND c.expiry_date<CURRENT_DATE THEN 'expired' ELSE 'active' END;
  INSERT INTO public.certificate_verifications(certificate_id,cert_number,verifier_type) VALUES(c.id,c.cert_number,'public');
  RETURN QUERY SELECT c.cert_number,c.student_name,c.course,c.specialization,c.issue_date,c.expiry_date,c.grade,c.duration,i.name,i.type,i.governorate,effective_status
  FROM public.institutions i WHERE i.id=c.institution_id AND i.status='approved';
END;$$;
GRANT EXECUTE ON FUNCTION public.verify_certificate(text) TO anon,authenticated;

CREATE OR REPLACE FUNCTION public.graduate_my_certificates()
RETURNS TABLE(cert_number text,course text,issue_date date,grade text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid(); phone text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT gp.phone INTO phone FROM public.graduate_profiles gp WHERE gp.auth_user_id=uid;
  IF phone IS NULL OR phone='' THEN RETURN; END IF;
  RETURN QUERY SELECT c.cert_number,c.course,c.issue_date,c.grade
  FROM public.certificates c JOIN public.institutions i ON i.id=c.institution_id
  WHERE c.student_phone=phone AND c.status='active' AND i.status='approved' ORDER BY c.issue_date DESC;
END;$$;
GRANT EXECUTE ON FUNCTION public.graduate_my_certificates() TO authenticated;

CREATE OR REPLACE FUNCTION public.company_search_candidates(p_qualification text DEFAULT NULL,p_governorate text DEFAULT NULL,p_year text DEFAULT NULL)
RETURNS TABLE(student_name text,course text,grade text,issue_date date,governorate text,student_phone text,institution_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid:=auth.uid();
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.companies WHERE auth_user_id=uid AND status='approved' AND search_credits>0) THEN RAISE EXCEPTION 'COMPANY_NOT_ALLOWED'; END IF;
  UPDATE public.companies SET search_credits=search_credits-1 WHERE auth_user_id=uid;
  RETURN QUERY SELECT c.student_name,c.course,c.grade,c.issue_date,c.governorate,c.student_phone,i.name
  FROM public.certificates c JOIN public.institutions i ON i.id=c.institution_id
  WHERE c.status='active' AND c.visible_to_companies=true
    AND (p_qualification IS NULL OR c.course ILIKE '%'||p_qualification||'%')
    AND (p_governorate IS NULL OR c.governorate=p_governorate)
    AND (p_year IS NULL OR EXTRACT(YEAR FROM c.issue_date)::text=p_year)
  ORDER BY c.issue_date DESC LIMIT 30;
END;$$;
GRANT EXECUTE ON FUNCTION public.company_search_candidates(text,text,text) TO authenticated;

-- Replace overly broad raw-company candidate access with the secure search function.
DROP POLICY IF EXISTS certificates_company_search ON public.certificates;

CREATE POLICY payments_owner_read ON public.payments FOR SELECT USING (public.is_admin() OR EXISTS(SELECT 1 FROM public.institution_users iu WHERE iu.institution_id=payments.institution_id AND iu.auth_user_id=auth.uid() AND iu.is_active=true));
CREATE POLICY payments_admin_all ON public.payments FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY notifications_self_read ON public.notifications FOR SELECT USING (auth.uid()=auth_user_id OR public.is_admin() OR EXISTS(SELECT 1 FROM public.institution_users iu WHERE iu.institution_id=notifications.institution_id AND iu.auth_user_id=auth.uid() AND iu.is_active=true));
CREATE POLICY notifications_self_update ON public.notifications FOR UPDATE USING (auth.uid()=auth_user_id OR public.is_admin()) WITH CHECK (auth.uid()=auth_user_id OR public.is_admin());
CREATE POLICY graduate_self_read ON public.graduate_profiles FOR SELECT USING (auth.uid()=auth_user_id OR public.is_admin() OR profile_public=true);
CREATE POLICY graduate_self_insert ON public.graduate_profiles FOR INSERT WITH CHECK (auth.uid()=auth_user_id);
CREATE POLICY graduate_self_update ON public.graduate_profiles FOR UPDATE USING (auth.uid()=auth_user_id OR public.is_admin()) WITH CHECK (auth.uid()=auth_user_id OR public.is_admin());

-- Atomic trigger-safe constraint: quota can never exceed total.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='institutions_quota_consistency') THEN
    ALTER TABLE public.institutions ADD CONSTRAINT institutions_quota_consistency CHECK (quota_used <= quota_total);
  END IF;
END $$;

-- Keep certificate sequence above existing numeric suffixes when repairing an old database.
DO $$ DECLARE max_n bigint; BEGIN
  SELECT COALESCE(MAX((substring(cert_number from '([0-9]+)$'))::bigint),0) INTO max_n FROM public.certificates WHERE cert_number ~ '[0-9]+$';
  IF max_n > 0 THEN PERFORM setval('public.certificate_number_seq', max_n, true); END IF;
EXCEPTION WHEN OTHERS THEN NULL; END $$;


CREATE OR REPLACE FUNCTION public.public_platform_stats()
RETURNS TABLE(institutions_count bigint, certificates_count bigint, verifications_count bigint)
LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  SELECT
    (SELECT count(*) FROM public.institutions WHERE status='approved'),
    (SELECT count(*) FROM public.certificates WHERE status='active'),
    (SELECT count(*) FROM public.certificate_verifications);
$$;
GRANT EXECUTE ON FUNCTION public.public_platform_stats() TO anon,authenticated;
