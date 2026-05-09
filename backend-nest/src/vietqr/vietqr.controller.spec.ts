import { VietQrController } from './vietqr.controller';

describe('VietQrController', () => {
  it('passes normalized request data to service', () => {
    const service = {
      create: jest.fn().mockReturnValue({ qrPayload: 'payload' }),
    };
    const controller = new VietQrController(service as any);

    expect(
      controller.create({
        amount: 250000,
        orderCode: 'DH-002',
        storeCode: 'HCM02',
      }),
    ).toEqual({ qrPayload: 'payload' });
    expect(service.create).toHaveBeenCalledWith({
      amount: 250000,
      orderCode: 'DH-002',
      storeCode: 'HCM02',
    });
  });
});
