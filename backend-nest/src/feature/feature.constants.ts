export const FEATURE_KEYS = {
  ADMIN: 'ADMIN',
  ADMIN_USERS: 'ADMIN_USERS',
  ADMIN_ROLES: 'ADMIN_ROLES',
  ADMIN_STORES: 'ADMIN_STORES',
  ADMIN_REGIONS: 'ADMIN_REGIONS',
  ADMIN_PERSONNEL: 'ADMIN_PERSONNEL',
  ADMIN_FEATURES: 'ADMIN_FEATURES',
  ADMIN_POLICIES: 'ADMIN_POLICIES',
  FIFO: 'FIFO',
  FIFO_IMPORT: 'FIFO_IMPORT',
  WARRANTY: 'WARRANTY',
  VIETQR: 'VIETQR',
  BANK_STATEMENTS: 'BANK_STATEMENTS',
  PAYMENT_MONITOR: 'PAYMENT_MONITOR',
  FEEDBACK: 'FEEDBACK',
} as const;

export const DEFAULT_FEATURE_DEFINITIONS = [
  { code: FEATURE_KEYS.ADMIN, displayName: 'Quản trị', description: 'Menu quản trị chung' },
  { code: FEATURE_KEYS.ADMIN_USERS, displayName: 'Quản lý người dùng', description: 'Tạo và sửa tài khoản nhân sự' },
  { code: FEATURE_KEYS.ADMIN_ROLES, displayName: 'Quản lý vai trò', description: 'Quản lý quyền hệ thống' },
  { code: FEATURE_KEYS.ADMIN_STORES, displayName: 'Quản lý SR', description: 'Quản lý showroom/SR và tài khoản liên quan' },
  { code: FEATURE_KEYS.ADMIN_REGIONS, displayName: 'Quản lý Vùng/Miền', description: 'Quản lý Miền, Vùng và scope ảo' },
  { code: FEATURE_KEYS.ADMIN_PERSONNEL, displayName: 'Quản lý phòng ban/chức danh', description: 'Quản lý catalog nhân sự' },
  { code: FEATURE_KEYS.ADMIN_FEATURES, displayName: 'Quản lý tính năng', description: 'Bật/tắt tính năng theo rule' },
  { code: FEATURE_KEYS.FIFO, displayName: 'FIFO', description: 'Kiểm tra và sắp xếp FIFO' },
  { code: FEATURE_KEYS.ADMIN_POLICIES, displayName: 'Qu?n l? policy', description: 'Qu?n l? rule quy?n v? c?u h?nh h? th?ng' },
  { code: FEATURE_KEYS.FIFO_IMPORT, displayName: 'Import tồn kho', description: 'Import tồn kho FIFO thủ công' },
  { code: FEATURE_KEYS.WARRANTY, displayName: 'BH / SC', description: 'Bảo hành và sửa chữa' },
  { code: FEATURE_KEYS.VIETQR, displayName: 'VietQR', description: 'Tạo QR chuyển khoản' },
  { code: FEATURE_KEYS.BANK_STATEMENTS, displayName: 'Sao kê', description: 'Rà soát sao kê MAP/VietinBank' },
  { code: FEATURE_KEYS.PAYMENT_MONITOR, displayName: 'Tiền vào', description: 'Theo dõi giao dịch tiền vào' },
  { code: FEATURE_KEYS.FEEDBACK, displayName: 'Phản hồi', description: 'Gửi phản hồi nội bộ' },
] as const;

export type FeatureKey = (typeof FEATURE_KEYS)[keyof typeof FEATURE_KEYS];
