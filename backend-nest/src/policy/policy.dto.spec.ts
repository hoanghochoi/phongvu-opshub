import { validate } from 'class-validator';
import { AdminSettingDto } from './policy.dto';

describe('AdminSettingDto', () => {
  it('accepts array-valued JSON settings', async () => {
    const dto = Object.assign(new AdminSettingDto(), {
      key: 'AUTH_ALLOWED_EMAIL_DOMAINS',
      displayName: 'Allowed domains',
      value: ['acare.vn', 'phongvu.vn'],
    });

    await expect(validate(dto)).resolves.toHaveLength(0);
  });
});
