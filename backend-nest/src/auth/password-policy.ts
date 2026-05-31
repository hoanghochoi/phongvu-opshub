import { BadRequestException } from '@nestjs/common';

export const PASSWORD_SPECIAL_PATTERN = /[!@#$%^&*(),.?":{}|<>]/;

export function passwordPolicyError(password: string): string | null {
  const errors: string[] = [];
  if (password.length < 8) errors.push('ít nhất 8 ký tự');
  if (!/[A-Z]/.test(password)) errors.push('ít nhất 1 chữ HOA');
  if (!/[0-9]/.test(password)) errors.push('ít nhất 1 số');
  if (!PASSWORD_SPECIAL_PATTERN.test(password)) {
    errors.push('ít nhất 1 ký tự đặc biệt');
  }
  return errors.length > 0 ? `Mật khẩu cần có ${errors.join(', ')}.` : null;
}

export function assertPasswordPolicy(password: string): void {
  const error = passwordPolicyError(password);
  if (error) throw new BadRequestException(error);
}
