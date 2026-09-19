-- ============================================================
-- منصة شهادتي - إعداد قاعدة البيانات الكامل
-- انسخ هذا الكود كله والصقه في SQL Editor في Supabase
-- ============================================================

-- تفعيل امتداد UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 1. جدول الباقات (Packages)
-- ============================================================
CREATE TABLE IF NOT EXISTS packages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,                        -- basic, bronze, silver, gold
  name_ar TEXT NOT NULL,                     -- الاسم بالعربي
  quota INTEGER NOT NULL,                    -- عدد الشهادات المسموح
  price_monthly NUMERIC(10,2) DEFAULT 0,
  price_yearly NUMERIC(10,2) DEFAULT 0,
  features JSONB DEFAULT '[]',               -- مميزات الباقة
  is_active BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 2. جدول المؤسسات (Institutions)
-- ============================================================
CREATE TABLE IF NOT EXISTS institutions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  name_en TEXT,
  logo_url TEXT,
  type TEXT DEFAULT 'training_center',       -- university, college, training_center, school, other
  governorate TEXT,
  address TEXT,
  contact_email TEXT UNIQUE NOT NULL,
  contact_phone TEXT,
  license_number TEXT,
  package_id UUID REFERENCES packages(id),
  status TEXT DEFAULT 'pending',             -- pending, approved, suspended, rejected
  quota_total INTEGER DEFAULT 0,
  quota_used INTEGER DEFAULT 0,
  subscription_start TIMESTAMPTZ,
  subscription_end TIMESTAMPTZ,
  policy_accepted BOOLEAN DEFAULT false,
  policy_accepted_at TIMESTAMPTZ,
  approved_at TIMESTAMPTZ,
  approved_by UUID,
  notes TEXT,                                -- ملاحظات الأدمن
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. جدول الشهادات (Certificates)
-- ============================================================
CREATE TABLE IF NOT EXISTS certificates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  cert_number TEXT UNIQUE NOT NULL,          -- الرقم الفريد للشهادة
  student_name TEXT NOT NULL,
  student_name_en TEXT,
  student_national_id TEXT,
  course TEXT NOT NULL,                      -- اسم الدورة / البرنامج
  specialization TEXT,                       -- التخصص
  issue_date DATE NOT NULL,
  expiry_date DATE,                          -- تاريخ انتهاء الصلاحية (اختياري)
  grade TEXT,                                -- التقدير
  grade_value NUMERIC(5,2),                  -- الدرجة رقمياً
  duration TEXT,                             -- مدة الدورة
  governorate TEXT,
  pdf_url TEXT,                              -- رابط PDF الشهادة
  qr_code TEXT,                              -- بيانات QR
  status TEXT DEFAULT 'active',              -- active, revoked, expired
  added_by TEXT DEFAULT 'institution',       -- institution, admin
  revoked_at TIMESTAMPTZ,
  revoke_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. جدول طلبات الاعتماد (Accreditation Requests)
-- ============================================================
CREATE TABLE IF NOT EXISTS accreditation_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_name TEXT NOT NULL,
  institution_type TEXT,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  contact_phone TEXT,
  governorate TEXT,
  license_number TEXT,
  license_doc_url TEXT,
  package_requested UUID REFERENCES packages(id),
  message TEXT,
  status TEXT DEFAULT 'new',                 -- new, reviewing, approved, rejected
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 5. جدول سجل العمليات (Activity Log)
-- ============================================================
CREATE TABLE IF NOT EXISTS activity_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_id UUID,                             -- من قام بالعملية
  actor_type TEXT,                           -- admin, institution
  action TEXT NOT NULL,                      -- create_cert, approve_inst, revoke_cert...
  target_type TEXT,                          -- certificate, institution, package...
  target_id UUID,
  details JSONB DEFAULT '{}',
  ip_address TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 6. جدول إعدادات النظام (Settings)
-- ============================================================
CREATE TABLE IF NOT EXISTS system_settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- تفعيل Row Level Security
-- ============================================================
ALTER TABLE packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;
ALTER TABLE accreditation_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Policies - الشهادات (عامة للتحقق)
-- ============================================================
CREATE POLICY "public_read_certificates" ON certificates
FOR SELECT USING (status = 'active');

CREATE POLICY "institution_insert_certificates" ON certificates
FOR INSERT WITH CHECK (
  auth.uid() IN (
    SELECT auth_user_id FROM institutions WHERE id = institution_id AND status = 'approved'
  )
);

CREATE POLICY "institution_read_own_certificates" ON certificates
FOR SELECT USING (
  auth.uid() IN (
    SELECT auth_user_id FROM institutions WHERE id = institution_id
  )
);

CREATE POLICY "institution_update_own_certificates" ON certificates
FOR UPDATE USING (
  auth.uid() IN (
    SELECT auth_user_id FROM institutions WHERE id = institution_id
  )
);

-- ============================================================
-- Policies - المؤسسات
-- ============================================================
CREATE POLICY "institution_read_own" ON institutions
FOR SELECT USING (auth.uid() = auth_user_id);

CREATE POLICY "institution_update_own" ON institutions
FOR UPDATE USING (auth.uid() = auth_user_id);

-- ============================================================
-- Policies - الباقات (عامة)
-- ============================================================
CREATE POLICY "public_read_packages" ON packages
FOR SELECT USING (is_active = true);

-- ============================================================
-- Policies - طلبات الاعتماد (أي شخص يقدر يرسل)
-- ============================================================
CREATE POLICY "public_insert_accreditation" ON accreditation_requests
FOR INSERT WITH CHECK (true);

-- ============================================================
-- بيانات أولية - الباقات
-- ============================================================
INSERT INTO packages (name, name_ar, quota, price_monthly, price_yearly, features, sort_order) VALUES
(
  'basic', 'الأساسية', 100, 0, 0,
  '["إصدار حتى 100 شهادة", "التحقق الرقمي", "QR Code لكل شهادة", "دعم فني بالبريد"]',
  1
),
(
  'bronze', 'البرونزية', 500, 99, 990,
  '["إصدار حتى 500 شهادة", "التحقق الرقمي", "QR Code لكل شهادة", "رفع جماعي Excel", "دعم فني مميز"]',
  2
),
(
  'silver', 'الفضية', 2000, 249, 2490,
  '["إصدار حتى 2000 شهادة", "التحقق الرقمي", "QR Code لكل شهادة", "رفع جماعي Excel", "PDF مخصص", "شعار المؤسسة على الشهادة", "دعم فني أولوية"]',
  3
),
(
  'gold', 'الذهبية', 10000, 499, 4990,
  '["إصدار غير محدود حتى 10,000", "التحقق الرقمي", "QR Code لكل شهادة", "رفع جماعي Excel", "PDF مخصص احترافي", "شعار المؤسسة على الشهادة", "API مخصص", "مدير حساب خاص", "تقارير متقدمة"]',
  4
);

-- ============================================================
-- بيانات أولية - إعدادات النظام
-- ============================================================
INSERT INTO system_settings (key, value, description) VALUES
('platform_name', 'شهادتي', 'اسم المنصة'),
('platform_name_en', 'Shehadaty', 'اسم المنصة بالإنجليزية'),
('support_email', 'support@shehadaty.com', 'بريد الدعم الفني'),
('cert_prefix', 'SHD', 'بادئة أرقام الشهادات'),
('maintenance_mode', 'false', 'وضع الصيانة');

-- ============================================================
-- Storage Bucket (نفذ هذا من لوحة Supabase > Storage)
-- ============================================================
-- أنشئ bucket باسم: certificates
-- اجعله Public: نعم
-- ============================================================

-- ============================================================
-- Function: توليد رقم شهادة تلقائي
-- ============================================================
CREATE OR REPLACE FUNCTION generate_cert_number()
RETURNS TEXT AS $$
DECLARE
  prefix TEXT;
  seq_num INTEGER;
  year_part TEXT;
BEGIN
  SELECT value INTO prefix FROM system_settings WHERE key = 'cert_prefix';
  year_part := TO_CHAR(NOW(), 'YYYY');
  seq_num := (SELECT COUNT(*) + 1 FROM certificates WHERE EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM NOW()));
  RETURN prefix || '-' || year_part || '-' || LPAD(seq_num::TEXT, 5, '0');
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- Function: تحديث updated_at تلقائياً
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER institutions_updated_at
  BEFORE UPDATE ON institutions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER certificates_updated_at
  BEFORE UPDATE ON certificates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- Function: تحديث quota_used تلقائياً عند إصدار شهادة
-- ============================================================
CREATE OR REPLACE FUNCTION update_quota_on_cert_insert()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE institutions
  SET quota_used = quota_used + 1
  WHERE id = NEW.institution_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER increment_quota_used
  AFTER INSERT ON certificates
  FOR EACH ROW EXECUTE FUNCTION update_quota_on_cert_insert();

-- ============================================================
-- تم الإعداد بنجاح ✅
-- الخطوات التالية:
-- 1. اذهب إلى Storage وأنشئ bucket باسم certificates واجعله Public
-- 2. اذهب إلى Authentication > Settings وفعّل Email Auth
-- 3. انسخ Project URL و anon key وضعهم في ملفات HTML
-- ============================================================

-- ============================================================
-- 7. تحديث جدول الشهادات - موافقة الطالب على الظهور للشركات
-- ============================================================
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS visible_to_companies BOOLEAN DEFAULT false;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS student_phone TEXT;
ALTER TABLE certificates ADD COLUMN IF NOT EXISTS consent_given_at TIMESTAMPTZ;

-- ============================================================
-- 8. جدول حسابات الشركات (Companies)
-- ============================================================
CREATE TABLE IF NOT EXISTS companies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  company_name TEXT NOT NULL,
  contact_name TEXT,
  contact_email TEXT UNIQUE NOT NULL,
  contact_phone TEXT,
  industry TEXT,
  status TEXT DEFAULT 'pending',           -- pending, approved, suspended
  subscription_tier TEXT DEFAULT 'free',   -- free, pro
  search_credits INTEGER DEFAULT 10,       -- عدد عمليات البحث المسموحة شهرياً
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "company_read_own" ON companies
FOR SELECT USING (auth.uid() = auth_user_id);

-- ============================================================
-- 9. جدول طلبات الترشيح (إذا الشركة مش مشتركة وعايزة ترشيح يدوي)
-- ============================================================
CREATE TABLE IF NOT EXISTS recruitment_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  contact_phone TEXT,
  qualification TEXT NOT NULL,             -- المؤهل المطلوب
  governorate TEXT,                        -- المحافظة
  graduation_year TEXT,
  positions_needed INTEGER DEFAULT 1,
  message TEXT,
  status TEXT DEFAULT 'new',               -- new, processing, fulfilled, closed
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE recruitment_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_insert_recruitment" ON recruitment_requests
FOR INSERT WITH CHECK (true);

-- ============================================================
-- 10. Policy: السماح للشركات المعتمدة بالبحث في الشهادات الموافق عليها فقط
-- ============================================================
CREATE POLICY "companies_search_consented_certs" ON certificates
FOR SELECT USING (
  visible_to_companies = true
  AND EXISTS (
    SELECT 1 FROM companies
    WHERE companies.auth_user_id = auth.uid()
    AND companies.status = 'approved'
  )
);

-- ============================================================
-- تم تحديث قاعدة البيانات لدعم محرك البحث عن الموظفين ✅
-- ============================================================
