import { UploadController } from './upload.controller';

describe('UploadController', () => {
  let controller: UploadController;
  let uploadService: {
    saveWarrantyImages: jest.Mock;
    getLinksString: jest.Mock;
  };

  beforeEach(() => {
    uploadService = {
      saveWarrantyImages: jest.fn(),
      getLinksString: jest.fn(),
    };
    controller = new UploadController(uploadService as any);
  });

  it('saves uploaded warranty images and upserts the warranty record', async () => {
    const files = [
      { originalname: 'receipt-1.jpg' },
      { originalname: 'receipt-2.png' },
    ] as Express.Multer.File[];
    const links = [
      'https://img.example.com/receipt/0.jpg',
      'https://img.example.com/receipt/1.png',
    ];
    uploadService.saveWarrantyImages.mockResolvedValue(links);
    uploadService.getLinksString.mockReturnValue(links.join(';'));

    await expect(
      controller.uploadWarrantyImages(
        { user: { id: 'user-1' } },
        { receipt: 'CP01-J12345678' },
        files,
      ),
    ).resolves.toEqual({
      status: 'success',
      receipt: 'CP01-J12345678',
      links,
      links_str: links.join(';'),
    });
    expect(uploadService.saveWarrantyImages).toHaveBeenCalledWith(
      'CP01-J12345678',
      files,
      'user-1',
    );
  });
});
