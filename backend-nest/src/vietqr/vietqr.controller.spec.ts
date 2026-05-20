import { VietQrController } from './vietqr.controller';

describe('VietQrController', () => {
  it('passes normalized request data to service', async () => {
    const service = {
      create: jest.fn().mockResolvedValue({ qrPayload: 'payload' }),
    };
    const controller = new VietQrController(service as any);

    await expect(
      controller.create({
        amount: 250000,
        orderCode: 'DH-002',
        storeCode: 'HCM02',
      }),
    ).resolves.toEqual({ qrPayload: 'payload' });
    expect(service.create).toHaveBeenCalledWith({
      amount: 250000,
      orderCode: 'DH-002',
      storeCode: 'HCM02',
    });
  });

  it('passes blank amount as null for editable VietQR amounts', async () => {
    const service = {
      create: jest.fn().mockResolvedValue({ qrPayload: 'payload' }),
    };
    const controller = new VietQrController(service as any);

    await controller.create({
      amount: '',
      orderCode: '',
      storeCode: 'HCM02',
    });

    expect(service.create).toHaveBeenCalledWith({
      amount: null,
      orderCode: '',
      storeCode: 'HCM02',
    });
  });
});
