import { VietQrController } from './vietqr.controller';

describe('VietQrController', () => {
  it('passes normalized request data to service', async () => {
    const service = {
      create: jest.fn().mockResolvedValue({ qrPayload: 'payload' }),
    };
    const controller = new VietQrController(service as any);

    await expect(
      controller.create(
        { user: { id: 'user-1' } },
        {
          amount: 250000,
          orderCode: 'DH-002',
          storeCode: 'HCM02',
        },
      ),
    ).resolves.toEqual({ qrPayload: 'payload' });
    expect(service.create).toHaveBeenCalledWith({
      amount: 250000,
      orderCode: 'DH-002',
      storeCode: 'HCM02',
      createdById: 'user-1',
    });
  });

  it('passes blank amount as null for editable VietQR amounts', async () => {
    const service = {
      create: jest.fn().mockResolvedValue({ qrPayload: 'payload' }),
    };
    const controller = new VietQrController(service as any);

    await controller.create(
      { user: { id: 'user-1' } },
      {
        amount: '',
        orderCode: '',
        storeCode: 'HCM02',
      },
    );

    expect(service.create).toHaveBeenCalledWith({
      amount: null,
      orderCode: '',
      storeCode: 'HCM02',
      createdById: 'user-1',
    });
  });

  it('passes confirm request to service', async () => {
    const service = {
      confirmPayment: jest.fn().mockResolvedValue({ confirmed: true }),
    };
    const controller = new VietQrController(service as any);

    await expect(
      controller.confirm({ user: { id: 'user-1' } }, 'payment-1'),
    ).resolves.toEqual({ confirmed: true });
    expect(service.confirmPayment).toHaveBeenCalledWith(
      { id: 'user-1' },
      'payment-1',
    );
  });

  it('creates n8n JSON VietQR response when external API key matches', async () => {
    const originalKey = process.env.VIETQR_EXTERNAL_API_KEY;
    process.env.VIETQR_EXTERNAL_API_KEY = 'external-secret';
    const service = {
      createExternal: jest.fn().mockResolvedValue({
        paymentId: 'payment-1',
        bankName: 'VietinBank',
        imageBase64: 'base64',
        imageBuffer: Buffer.from('png'),
      }),
    };
    const controller = new VietQrController(service as any);

    try {
      await expect(
        controller.createExternalFromQuery(
          { headers: { 'x-opshub-vietqr-key': 'external-secret' } },
          {
            amount: '250,000',
            addInfo: 'DH-002 HCM02 BOT',
            store: 'HCM02',
          },
        ),
      ).resolves.toEqual({
        paymentId: 'payment-1',
        bankName: 'VietinBank',
        imageBase64: 'base64',
      });
    } finally {
      restoreExternalApiKey(originalKey);
    }

    expect(service.createExternal).toHaveBeenCalledWith({
      amount: 250000,
      orderCode: null,
      transferContent: 'DH-002 HCM02 BOT',
      addInfo: 'DH-002 HCM02 BOT',
      storeCode: 'HCM02',
      source: 'n8n',
    });
  });

  it('rejects n8n calls with an invalid external API key', async () => {
    const originalKey = process.env.VIETQR_EXTERNAL_API_KEY;
    process.env.VIETQR_EXTERNAL_API_KEY = 'external-secret';
    const controller = new VietQrController({
      createExternal: jest.fn(),
    } as any);

    try {
      await expect(
        controller.createExternalFromQuery(
          { headers: { 'x-opshub-vietqr-key': 'wrong' } },
          { storeCode: 'HCM02' },
        ),
      ).rejects.toMatchObject({ status: 401 });
    } finally {
      restoreExternalApiKey(originalKey);
    }
  });

  it('returns n8n image bytes with transfer headers', async () => {
    const originalKey = process.env.VIETQR_EXTERNAL_API_KEY;
    process.env.VIETQR_EXTERNAL_API_KEY = 'external-secret';
    const imageBuffer = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
    const service = {
      createExternal: jest.fn().mockResolvedValue({
        paymentId: 'payment-1',
        bankName: 'VietinBank',
        accountNumber: '18PVICU',
        accountName: 'CTY PHONG VU',
        amount: 250000,
        transferContent: 'DH-002 HCM02 BOT',
        qrBrand: {
          key: 'phongvu',
          title: 'Phong Vũ',
          logoKey: 'phongvu',
          logoAsset: 'assets/icon/source/app_icon_master.png',
        },
        imageMimeType: 'image/png',
        imageFileName: 'vietqr_DH-002_HCM02_BOT.png',
        imageBuffer,
      }),
    };
    const controller = new VietQrController(service as any);
    const res = { setHeader: jest.fn(), send: jest.fn() };

    try {
      await controller.createExternalImage(
        { headers: { authorization: 'Bearer external-secret' } },
        { amount: '250000', orderCode: 'DH-002', storeCode: 'HCM02' },
        res as any,
      );
    } finally {
      restoreExternalApiKey(originalKey);
    }

    expect(res.setHeader).toHaveBeenCalledWith('Content-Type', 'image/png');
    expect(res.setHeader).toHaveBeenCalledWith(
      'X-OpsHub-Transfer-Content',
      'DH-002 HCM02 BOT',
    );
    expect(res.setHeader).toHaveBeenCalledWith('X-OpsHub-Brand-Key', 'phongvu');
    expect(res.setHeader).toHaveBeenCalledWith(
      'X-OpsHub-Brand-Title',
      'Phong Vũ',
    );
    expect(res.send).toHaveBeenCalledWith(imageBuffer);
  });

  it('returns n8n payment status by payment id', async () => {
    const originalKey = process.env.VIETQR_EXTERNAL_API_KEY;
    process.env.VIETQR_EXTERNAL_API_KEY = 'external-secret';
    const service = {
      getExternalStatus: jest.fn().mockResolvedValue({
        paymentId: 'payment-1',
        status: 'PENDING',
        confirmed: false,
      }),
    };
    const controller = new VietQrController(service as any);

    try {
      await expect(
        controller.externalStatusFromQuery(
          { headers: { 'x-opshub-vietqr-key': 'external-secret' } },
          { paymentId: 'payment-1' },
        ),
      ).resolves.toEqual({
        paymentId: 'payment-1',
        status: 'PENDING',
        confirmed: false,
      });
    } finally {
      restoreExternalApiKey(originalKey);
    }

    expect(service.getExternalStatus).toHaveBeenCalledWith('payment-1');
  });

  it('checks n8n payment status when requested', async () => {
    const originalKey = process.env.VIETQR_EXTERNAL_API_KEY;
    process.env.VIETQR_EXTERNAL_API_KEY = 'external-secret';
    const service = {
      checkExternalStatus: jest.fn().mockResolvedValue({
        paymentId: 'payment-1',
        status: 'PAID',
        confirmed: true,
      }),
    };
    const controller = new VietQrController(service as any);

    try {
      await expect(
        controller.externalStatusFromBody(
          { headers: { authorization: 'Bearer external-secret' } },
          { id: 'payment-1', check: true },
        ),
      ).resolves.toEqual({
        paymentId: 'payment-1',
        status: 'PAID',
        confirmed: true,
      });
    } finally {
      restoreExternalApiKey(originalKey);
    }

    expect(service.checkExternalStatus).toHaveBeenCalledWith('payment-1');
  });
});

function restoreExternalApiKey(value: string | undefined) {
  if (value === undefined) {
    delete process.env.VIETQR_EXTERNAL_API_KEY;
    return;
  }
  process.env.VIETQR_EXTERNAL_API_KEY = value;
}
