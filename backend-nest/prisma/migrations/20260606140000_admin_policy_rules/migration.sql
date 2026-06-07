-- Admin policy definitions and rules: move runtime authorization defaults out of code.
CREATE TABLE "AdminPolicyDefinition" (
  "id" TEXT NOT NULL,
  "code" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "description" TEXT,
  "category" TEXT NOT NULL DEFAULT 'GENERAL',
  "defaultAllowed" BOOLEAN NOT NULL DEFAULT false,
  "isSystem" BOOLEAN NOT NULL DEFAULT true,
  "isActive" BOOLEAN NOT NULL DEFAULT true,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminPolicyDefinition_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "AdminPolicyRule" (
  "id" TEXT NOT NULL,
  "policyCode" TEXT NOT NULL,
  "allowed" BOOLEAN NOT NULL,
  "emailDomain" TEXT,
  "systemRole" TEXT,
  "departmentCode" TEXT,
  "jobRoleCode" TEXT,
  "workScopeType" TEXT,
  "regionCode" TEXT,
  "areaCode" TEXT,
  "storeCode" TEXT,
  "userId" TEXT,
  "scopeContains" TEXT,
  "note" TEXT,
  "isSystem" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminPolicyRule_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "AdminSetting" (
  "id" TEXT NOT NULL,
  "key" TEXT NOT NULL,
  "displayName" TEXT NOT NULL,
  "description" TEXT,
  "value" JSONB NOT NULL,
  "category" TEXT NOT NULL DEFAULT 'GENERAL',
  "isSystem" BOOLEAN NOT NULL DEFAULT true,
  "isSensitive" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "AdminSetting_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AdminPolicyDefinition_code_key" ON "AdminPolicyDefinition"("code");
CREATE INDEX "AdminPolicyRule_policyCode_idx" ON "AdminPolicyRule"("policyCode");
CREATE INDEX "AdminPolicyRule_emailDomain_idx" ON "AdminPolicyRule"("emailDomain");
CREATE INDEX "AdminPolicyRule_systemRole_idx" ON "AdminPolicyRule"("systemRole");
CREATE INDEX "AdminPolicyRule_departmentCode_idx" ON "AdminPolicyRule"("departmentCode");
CREATE INDEX "AdminPolicyRule_jobRoleCode_idx" ON "AdminPolicyRule"("jobRoleCode");
CREATE INDEX "AdminPolicyRule_workScopeType_idx" ON "AdminPolicyRule"("workScopeType");
CREATE INDEX "AdminPolicyRule_regionCode_idx" ON "AdminPolicyRule"("regionCode");
CREATE INDEX "AdminPolicyRule_areaCode_idx" ON "AdminPolicyRule"("areaCode");
CREATE INDEX "AdminPolicyRule_storeCode_idx" ON "AdminPolicyRule"("storeCode");
CREATE INDEX "AdminPolicyRule_userId_idx" ON "AdminPolicyRule"("userId");
CREATE UNIQUE INDEX "AdminSetting_key_key" ON "AdminSetting"("key");
CREATE INDEX "AdminSetting_category_idx" ON "AdminSetting"("category");

ALTER TABLE "AdminPolicyRule" ADD CONSTRAINT "AdminPolicyRule_policyCode_fkey" FOREIGN KEY ("policyCode") REFERENCES "AdminPolicyDefinition"("code") ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "AdminPolicyDefinition" ("id", "code", "displayName", "description", "category", "defaultAllowed", "isSystem", "isActive") VALUES
  ('policy-admin', 'ADMIN', 'Quản trị', 'Menu quản trị chung', 'FEATURE', false, true, true),
  ('policy-admin-users', 'ADMIN_USERS', 'Quản lý người dùng', 'Tạo và sửa tài khoản nhân sự', 'FEATURE', false, true, true),
  ('policy-admin-roles', 'ADMIN_ROLES', 'Quản lý vai trò', 'Quản lý quyền hệ thống', 'FEATURE', false, true, true),
  ('policy-admin-stores', 'ADMIN_STORES', 'Quản lý SR', 'Quản lý showroom/SR', 'FEATURE', false, true, true),
  ('policy-admin-regions', 'ADMIN_REGIONS', 'Quản lý Vùng/Miền', 'Quản lý Miền, Vùng và scope ảo', 'FEATURE', false, true, true),
  ('policy-admin-personnel', 'ADMIN_PERSONNEL', 'Quản lý phòng ban/chức danh', 'Quản lý catalog nhân sự', 'FEATURE', false, true, true),
  ('policy-admin-features', 'ADMIN_FEATURES', 'Quản lý tính năng', 'Bật/tắt tính năng theo rule', 'FEATURE', false, true, true),
  ('policy-admin-policies', 'ADMIN_POLICIES', 'Quản lý policy', 'Quản lý rule quyền và cấu hình hệ thống', 'FEATURE', false, true, true),
  ('policy-fifo', 'FIFO', 'FIFO', 'Kiểm tra và sắp xếp FIFO', 'FEATURE', false, true, true),
  ('policy-fifo-import', 'FIFO_IMPORT', 'Import tồn kho', 'Import tồn kho FIFO thủ công', 'FEATURE', false, true, true),
  ('policy-warranty', 'WARRANTY', 'BH / SC', 'Bảo hành và sửa chữa', 'FEATURE', false, true, true),
  ('policy-vietqr', 'VIETQR', 'VietQR', 'Tạo QR chuyển khoản', 'FEATURE', true, true, true),
  ('policy-bank-statements', 'BANK_STATEMENTS', 'Sao kê', 'Rà soát sao kê MAP/VietinBank', 'FEATURE', false, true, true),
  ('policy-payment-monitor', 'PAYMENT_MONITOR', 'Tiền vào', 'Theo dõi giao dịch tiền vào', 'FEATURE', true, true, true),
  ('policy-feedback', 'FEEDBACK', 'Phản hồi', 'Gửi phản hồi nội bộ', 'FEATURE', true, true, true),
  ('policy-admin-user-role-edit', 'ADMIN_USER_ROLE_EDIT', 'Sửa role user', 'Quyền đổi system role của user', 'ADMIN_CAPABILITY', false, true, true),
  ('policy-admin-store-create', 'ADMIN_STORE_CREATE', 'Tạo SR', 'Quyền tạo SR/showroom', 'ADMIN_CAPABILITY', false, true, true),
  ('policy-admin-store-scope-edit', 'ADMIN_STORE_SCOPE_EDIT', 'Đổi Vùng/Miền SR', 'Quyền đổi Vùng/Miền của SR', 'ADMIN_CAPABILITY', false, true, true),
  ('policy-fifo-log-admin', 'FIFO_LOG_ADMIN', 'Xem lịch sử FIFO admin', 'Quyền xem lịch sử FIFO quản trị', 'DATA_SCOPE', false, true, true),
  ('policy-warranty-all-scope', 'WARRANTY_ALL_SCOPE', 'Xem toàn bộ bảo hành', 'Quyền đọc bảo hành toàn hệ thống', 'DATA_SCOPE', false, true, true),
  ('policy-statement-all-scope', 'BANK_STATEMENT_ALL_SCOPE', 'Xem sao kê toàn hệ thống', 'Quyền đọc sao kê toàn bộ SR', 'DATA_SCOPE', false, true, true),
  ('policy-payment-all-scope', 'PAYMENT_MONITOR_ALL_SCOPE', 'Theo dõi tiền vào toàn hệ thống', 'Quyền chọn SR khi theo dõi tiền vào', 'DATA_SCOPE', false, true, true)
ON CONFLICT ("code") DO NOTHING;

INSERT INTO "AdminPolicyRule" ("id", "policyCode", "allowed", "systemRole", "scopeContains", "note", "isSystem") VALUES
  ('rule-admin-admin-role', 'ADMIN', true, 'ADMIN', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-acare-role', 'ADMIN', true, 'ADMIN_ACARE', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-manager-role', 'ADMIN', true, 'MANAGER', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-users-admin-role', 'ADMIN_USERS', true, 'ADMIN', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-users-acare-role', 'ADMIN_USERS', true, 'ADMIN_ACARE', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-users-manager-role', 'ADMIN_USERS', true, 'MANAGER', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-stores-admin-role', 'ADMIN_STORES', true, 'ADMIN', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-stores-acare-role', 'ADMIN_STORES', true, 'ADMIN_ACARE', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-admin-stores-manager-role', 'ADMIN_STORES', true, 'MANAGER', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-fifo-cp62', 'FIFO', true, NULL, 'CP62', 'Seed từ CP62 restricted flow', true),
  ('rule-warranty-cp62', 'WARRANTY', true, NULL, 'CP62', 'Seed từ CP62 restricted flow', true),
  ('rule-fifo-import-admin', 'FIFO_IMPORT', true, 'ADMIN', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-fifo-import-acare', 'FIFO_IMPORT', true, 'ADMIN_ACARE', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-bank-statements-manager', 'BANK_STATEMENTS', true, 'MANAGER', NULL, 'Seed từ fallback role hardcode', true),
  ('rule-user-role-edit-super', 'ADMIN_USER_ROLE_EDIT', true, 'SUPER_ADMIN', NULL, 'Break-glass role edit default', true),
  ('rule-store-create-super', 'ADMIN_STORE_CREATE', true, 'SUPER_ADMIN', NULL, 'Seed từ store create hardcode', true),
  ('rule-store-scope-edit-super', 'ADMIN_STORE_SCOPE_EDIT', true, 'SUPER_ADMIN', NULL, 'Seed từ store scope edit hardcode', true),
  ('rule-fifo-log-admin-super', 'FIFO_LOG_ADMIN', true, 'SUPER_ADMIN', NULL, 'Seed từ FIFO log hardcode', true),
  ('rule-fifo-log-admin-admin', 'FIFO_LOG_ADMIN', true, 'ADMIN', NULL, 'Seed từ FIFO log hardcode', true),
  ('rule-warranty-all-super', 'WARRANTY_ALL_SCOPE', true, 'SUPER_ADMIN', NULL, 'Seed từ warranty scope hardcode', true),
  ('rule-statement-all-super', 'BANK_STATEMENT_ALL_SCOPE', true, 'SUPER_ADMIN', NULL, 'Seed từ sao kê scope hardcode', true),
  ('rule-payment-all-super', 'PAYMENT_MONITOR_ALL_SCOPE', true, 'SUPER_ADMIN', NULL, 'Seed từ tiền vào scope hardcode', true)
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "AdminSetting" ("id", "key", "displayName", "description", "value", "category", "isSystem", "isSensitive") VALUES
  ('setting-auth-domains', 'AUTH_ALLOWED_EMAIL_DOMAINS', 'Domain đăng nhập', 'Danh sách domain email được đăng ký/đăng nhập', '["phongvu-shop.vn","phongvu-mna.vn","phongvu-care.vn","phongvu-office.vn","phongvu.vn","teko.vn","acaretek.vn"]'::jsonb, 'AUTH', true, false),
  ('setting-password-policy', 'AUTH_PASSWORD_POLICY', 'Chính sách mật khẩu', 'Độ mạnh mật khẩu tối thiểu', '{"minLength":8,"requireUppercase":true,"requireNumber":true,"requireSpecial":true}'::jsonb, 'AUTH', true, false),
  ('setting-registration-otp', 'AUTH_REGISTRATION_OTP_POLICY', 'OTP đăng ký', 'Thời hạn và số lần nhập mã đăng ký', '{"ttlMinutes":10,"maxAttempts":5}'::jsonb, 'AUTH', true, false),
  ('setting-reset-otp', 'AUTH_RESET_OTP_POLICY', 'OTP đổi mật khẩu', 'Thời hạn và số lần nhập mã đổi mật khẩu', '{"ttlMinutes":10,"maxAttempts":5}'::jsonb, 'AUTH', true, false)
ON CONFLICT ("key") DO NOTHING;
