export const ADMIN_POLICY_CODES = {
  ADMIN: 'ADMIN',
  ADMIN_USERS: 'ADMIN_USERS',
  ADMIN_ROLES: 'ADMIN_ROLES',
  ADMIN_STORES: 'ADMIN_STORES',
  ADMIN_REGIONS: 'ADMIN_REGIONS',
  ADMIN_PERSONNEL: 'ADMIN_PERSONNEL',
  ADMIN_FEATURES: 'ADMIN_FEATURES',
  ADMIN_POLICIES: 'ADMIN_POLICIES',
  ADMIN_FEEDBACK: 'ADMIN_FEEDBACK',
  FIFO: 'FIFO',
  FIFO_IMPORT: 'FIFO_IMPORT',
  WARRANTY: 'WARRANTY',
  VIETQR: 'VIETQR',
  BANK_STATEMENTS: 'BANK_STATEMENTS',
  PAYMENT_MONITOR: 'PAYMENT_MONITOR',
  FEEDBACK: 'FEEDBACK',
  ADMIN_USER_ROLE_EDIT: 'ADMIN_USER_ROLE_EDIT',
  ADMIN_STORE_CREATE: 'ADMIN_STORE_CREATE',
  ADMIN_STORE_SCOPE_EDIT: 'ADMIN_STORE_SCOPE_EDIT',
  FIFO_LOG_ADMIN: 'FIFO_LOG_ADMIN',
  WARRANTY_ALL_SCOPE: 'WARRANTY_ALL_SCOPE',
  BANK_STATEMENT_ALL_SCOPE: 'BANK_STATEMENT_ALL_SCOPE',
  PAYMENT_MONITOR_ALL_SCOPE: 'PAYMENT_MONITOR_ALL_SCOPE',
} as const;

export const ADMIN_SETTING_KEYS = {
  AUTH_ALLOWED_EMAIL_DOMAINS: 'AUTH_ALLOWED_EMAIL_DOMAINS',
  AUTH_PASSWORD_POLICY: 'AUTH_PASSWORD_POLICY',
  AUTH_REGISTRATION_OTP_POLICY: 'AUTH_REGISTRATION_OTP_POLICY',
  AUTH_RESET_OTP_POLICY: 'AUTH_RESET_OTP_POLICY',
} as const;

export const DEFAULT_AUTH_DOMAINS = ['phongvu.vn', 'acaretek.vn'];

export const DEFAULT_ADMIN_POLICY_DEFINITIONS = [
  {
    code: ADMIN_POLICY_CODES.ADMIN,
    displayName: 'Quản trị',
    description: 'Menu quản trị chung',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_USERS,
    displayName: 'Quản lý người dùng',
    description: 'Tạo và sửa tài khoản nhân sự',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_ROLES,
    displayName: 'Quản lý vai trò',
    description: 'Quản lý quyền hệ thống',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_STORES,
    displayName: 'Quản lý SR',
    description: 'Quản lý showroom/SR',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_REGIONS,
    displayName: 'Quản lý Vùng/Miền',
    description: 'Quản lý Miền, Vùng và scope ảo',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_PERSONNEL,
    displayName: 'Quản lý phòng ban/chức danh',
    description: 'Quản lý catalog nhân sự',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_FEATURES,
    displayName: 'Quản lý tính năng',
    description: 'Bật/tắt tính năng theo rule',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_POLICIES,
    displayName: 'Quản lý policy',
    description: 'Quản lý rule quyền và cấu hình hệ thống',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_FEEDBACK,
    displayName: 'Danh sách phản hồi',
    description: 'Xem danh sách phản hồi nội bộ',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.FIFO,
    displayName: 'FIFO',
    description: 'Kiểm tra và sắp xếp FIFO',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.FIFO_IMPORT,
    displayName: 'Import tồn kho',
    description: 'Import tồn kho FIFO thủ công',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.WARRANTY,
    displayName: 'BH / SC',
    description: 'Bảo hành và sửa chữa',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.VIETQR,
    displayName: 'VietQR',
    description: 'Tạo QR chuyển khoản',
    category: 'FEATURE',
    defaultAllowed: true,
  },
  {
    code: ADMIN_POLICY_CODES.BANK_STATEMENTS,
    displayName: 'Sao kê',
    description: 'Rà soát sao kê MAP/VietinBank',
    category: 'FEATURE',
  },
  {
    code: ADMIN_POLICY_CODES.PAYMENT_MONITOR,
    displayName: 'Tiền vào',
    description: 'Theo dõi giao dịch tiền vào',
    category: 'FEATURE',
    defaultAllowed: true,
  },
  {
    code: ADMIN_POLICY_CODES.FEEDBACK,
    displayName: 'Phản hồi',
    description: 'Gửi phản hồi nội bộ',
    category: 'FEATURE',
    defaultAllowed: true,
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_USER_ROLE_EDIT,
    displayName: 'Sửa role user',
    description: 'Quyền đổi system role của user',
    category: 'ADMIN_CAPABILITY',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_STORE_CREATE,
    displayName: 'Tạo SR',
    description: 'Quyền tạo SR/showroom',
    category: 'ADMIN_CAPABILITY',
  },
  {
    code: ADMIN_POLICY_CODES.ADMIN_STORE_SCOPE_EDIT,
    displayName: 'Đổi Vùng/Miền SR',
    description: 'Quyền đổi Vùng/Miền của SR',
    category: 'ADMIN_CAPABILITY',
  },
  {
    code: ADMIN_POLICY_CODES.FIFO_LOG_ADMIN,
    displayName: 'Xem lịch sử FIFO admin',
    description: 'Quyền xem lịch sử FIFO quản trị',
    category: 'DATA_SCOPE',
  },
  {
    code: ADMIN_POLICY_CODES.WARRANTY_ALL_SCOPE,
    displayName: 'Xem toàn bộ bảo hành',
    description: 'Quyền đọc bảo hành toàn hệ thống',
    category: 'DATA_SCOPE',
  },
  {
    code: ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
    displayName: 'Xem sao kê toàn hệ thống',
    description: 'Quyền đọc sao kê toàn bộ SR',
    category: 'DATA_SCOPE',
  },
  {
    code: ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
    displayName: 'Theo dõi tiền vào toàn hệ thống',
    description: 'Quyền chọn SR khi theo dõi tiền vào',
    category: 'DATA_SCOPE',
  },
];

export const DEFAULT_ADMIN_POLICY_RULES = [
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN,
    allowed: true,
    systemRole: 'ADMIN_PHONGVU',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN,
    allowed: true,
    systemRole: 'ADMIN_ACARE',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN,
    allowed: true,
    systemRole: 'MANAGER',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
    allowed: true,
    systemRole: 'ADMIN_PHONGVU',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
    allowed: true,
    systemRole: 'ADMIN_ACARE',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_USERS,
    allowed: true,
    systemRole: 'MANAGER',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_STORES,
    allowed: true,
    systemRole: 'ADMIN_PHONGVU',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_STORES,
    allowed: true,
    systemRole: 'ADMIN_ACARE',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_STORES,
    allowed: true,
    systemRole: 'MANAGER',
  },
  { policyCode: ADMIN_POLICY_CODES.FIFO, allowed: true, scopeContains: 'CP62' },
  {
    policyCode: ADMIN_POLICY_CODES.WARRANTY,
    allowed: true,
    scopeContains: 'CP62',
  },
  {
    policyCode: ADMIN_POLICY_CODES.FIFO_IMPORT,
    allowed: true,
    systemRole: 'ADMIN_PHONGVU',
  },
  {
    policyCode: ADMIN_POLICY_CODES.FIFO_IMPORT,
    allowed: true,
    systemRole: 'ADMIN_ACARE',
  },
  {
    policyCode: ADMIN_POLICY_CODES.BANK_STATEMENTS,
    allowed: true,
    systemRole: 'MANAGER',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_USER_ROLE_EDIT,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_STORE_CREATE,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.ADMIN_STORE_SCOPE_EDIT,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.FIFO_LOG_ADMIN,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.FIFO_LOG_ADMIN,
    allowed: true,
    systemRole: 'ADMIN_PHONGVU',
  },
  {
    policyCode: ADMIN_POLICY_CODES.WARRANTY_ALL_SCOPE,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.BANK_STATEMENT_ALL_SCOPE,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
  {
    policyCode: ADMIN_POLICY_CODES.PAYMENT_MONITOR_ALL_SCOPE,
    allowed: true,
    systemRole: 'SUPER_ADMIN',
  },
];

export const DEFAULT_ADMIN_SETTINGS = [
  {
    key: ADMIN_SETTING_KEYS.AUTH_ALLOWED_EMAIL_DOMAINS,
    displayName: 'Domain đăng nhập',
    description: 'Danh sách domain email được đăng ký/đăng nhập',
    category: 'AUTH',
    value: DEFAULT_AUTH_DOMAINS,
  },
  {
    key: ADMIN_SETTING_KEYS.AUTH_PASSWORD_POLICY,
    displayName: 'Chính sách mật khẩu',
    description: 'Độ mạnh mật khẩu tối thiểu',
    category: 'AUTH',
    value: {
      minLength: 8,
      requireUppercase: true,
      requireNumber: true,
      requireSpecial: true,
    },
  },
  {
    key: ADMIN_SETTING_KEYS.AUTH_REGISTRATION_OTP_POLICY,
    displayName: 'OTP đăng ký',
    description: 'Thời hạn và số lần nhập mã đăng ký',
    category: 'AUTH',
    value: { ttlMinutes: 10, maxAttempts: 5 },
  },
  {
    key: ADMIN_SETTING_KEYS.AUTH_RESET_OTP_POLICY,
    displayName: 'OTP đổi mật khẩu',
    description: 'Thời hạn và số lần nhập mã đổi mật khẩu',
    category: 'AUTH',
    value: { ttlMinutes: 10, maxAttempts: 5 },
  },
];
