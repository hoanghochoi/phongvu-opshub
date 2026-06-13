import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { UploadWarrantyImagesDto } from './upload.dto';

function validateWarrantyUploadBody(body: Record<string, unknown>) {
  return validateSync(plainToInstance(UploadWarrantyImagesDto, body), {
    forbidNonWhitelisted: true,
    whitelist: true,
  });
}

describe('UploadWarrantyImagesDto', () => {
  it('accepts legacy user metadata while keeping receipt as source contract', () => {
    const errors = validateWarrantyUploadBody({
      receipt: 'CP62-J12345678',
      user: 'staff@phongvu.vn',
    });

    expect(errors).toHaveLength(0);
  });

  it('still rejects unrelated fields', () => {
    const errors = validateWarrantyUploadBody({
      receipt: 'CP62-J12345678',
      storeId: 'CP62',
    });

    expect(errors).toHaveLength(1);
    expect(errors[0].constraints).toHaveProperty('whitelistValidation');
  });
});
