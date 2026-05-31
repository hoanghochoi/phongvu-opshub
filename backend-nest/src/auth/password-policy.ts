import { BadRequestException } from '@nestjs/common';

export const PASSWORD_SPECIAL_PATTERN = /[!@#$%^&*(),.?":{}|<>]/;

export function passwordPolicyError(password: string): string | null {
  const errors: string[] = [];
  if (password.length < 8) errors.push('it nhat 8 ky tu');
  if (!/[A-Z]/.test(password)) errors.push('it nhat 1 chu HOA');
  if (!/[0-9]/.test(password)) errors.push('it nhat 1 so');
  if (!PASSWORD_SPECIAL_PATTERN.test(password)) {
    errors.push('it nhat 1 ky tu dac biet');
  }
  return errors.length > 0 ? `Mat khau can co ${errors.join(', ')}.` : null;
}

export function assertPasswordPolicy(password: string): void {
  const error = passwordPolicyError(password);
  if (error) throw new BadRequestException(error);
}
