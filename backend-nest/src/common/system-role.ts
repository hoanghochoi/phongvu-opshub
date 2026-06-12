export const SYSTEM_ROLE_SUPER_ADMIN = 'SUPER_ADMIN';
export const SYSTEM_ROLE_ADMIN = 'ADMIN';
export const SYSTEM_ROLE_USER = 'USER';

export const SYSTEM_ROLE_CODES = [
  SYSTEM_ROLE_SUPER_ADMIN,
  SYSTEM_ROLE_ADMIN,
  SYSTEM_ROLE_USER,
] as const;

const ROLE_ALIASES: Record<string, string> = {
  ADMIN_PHONGVU: SYSTEM_ROLE_ADMIN,
  ADMIN_ACARE: SYSTEM_ROLE_ADMIN,
  MANAGER: SYSTEM_ROLE_ADMIN,
  STAFF: SYSTEM_ROLE_USER,
};

export function normalizeSystemRoleCode(role: unknown) {
  const code = String(role || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_]/g, '_');
  if (!code) return null;
  return ROLE_ALIASES[code] ?? code;
}

export function isSuperAdminRole(role: unknown) {
  return normalizeSystemRoleCode(role) === SYSTEM_ROLE_SUPER_ADMIN;
}

export function isAdminRole(role: unknown) {
  return normalizeSystemRoleCode(role) === SYSTEM_ROLE_ADMIN;
}

export function isSystemRoleCode(role: unknown) {
  const code = normalizeSystemRoleCode(role);
  return Boolean(code && SYSTEM_ROLE_CODES.includes(code as any));
}
