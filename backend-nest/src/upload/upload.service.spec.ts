import { ForbiddenException } from '@nestjs/common';
import { UploadService } from './upload.service';

describe('UploadService', () => {
  let service: UploadService;
  let prisma: any;
  let privateMediaService: any;

  beforeEach(() => {
    prisma = {
      user: { findUnique: jest.fn() },
      warranty: {
        upsert: jest.fn(),
        update: jest.fn(),
      },
    };
    privateMediaService = {
      saveImages: jest.fn(),
      discardUrls: jest.fn(),
      savePublicHelpImage: jest.fn(),
    };
    service = new UploadService(prisma, privateMediaService);
  });

  it('joins and parses semicolon-separated image links', () => {
    const links = [
      'https://api.example.com/api/media/media-1',
      'https://api.example.com/api/media/media-2',
    ];

    expect(service.getLinksString(links)).toBe(links.join(';'));
    expect(service.parseLinksString('a.jpg;; b.jpg ;')).toEqual([
      'a.jpg',
      'b.jpg',
    ]);
  });

  it('stores warranty images as private opaque media', async () => {
    const files = [{ originalname: 'receipt.jpg' }] as Express.Multer.File[];
    const links = ['https://api.example.com/api/media/media-1'];
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      storeId: 'store-1',
      role: 'USER',
    });
    prisma.warranty.upsert.mockResolvedValue({
      id: 'warranty-1',
      createdById: 'user-1',
      imageLinks: 'https://api.example.com/api/media/media-old',
      createdBy: { storeId: 'store-1' },
    });
    prisma.warranty.update.mockResolvedValue({ id: 'warranty-1' });
    privateMediaService.saveImages.mockResolvedValue(links);

    await expect(
      service.saveWarrantyImages('CP01-J12345678', files, 'user-1'),
    ).resolves.toEqual(links);

    expect(privateMediaService.saveImages).toHaveBeenCalledWith({
      ownerFeature: 'WARRANTY',
      ownerRecordId: 'warranty-1',
      uploaderId: 'user-1',
      files,
    });
    expect(prisma.warranty.update).toHaveBeenCalledWith({
      where: { id: 'warranty-1' },
      data: { imageLinks: links[0] },
    });
    expect(privateMediaService.discardUrls).toHaveBeenCalledWith([
      'https://api.example.com/api/media/media-old',
    ]);
  });

  it('blocks replacing warranty images across showroom scope', async () => {
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-2',
      storeId: 'store-2',
      role: 'USER',
    });
    prisma.warranty.upsert.mockResolvedValue({
      id: 'warranty-1',
      createdById: 'user-1',
      imageLinks: null,
      createdBy: { storeId: 'store-1' },
    });

    await expect(
      service.saveWarrantyImages('CP01-J12345678', [], 'user-2'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(privateMediaService.saveImages).not.toHaveBeenCalled();
  });

  it('rolls private media back when the warranty metadata update fails', async () => {
    const links = ['https://api.example.com/api/media/media-1'];
    prisma.user.findUnique.mockResolvedValue({
      id: 'user-1',
      storeId: 'store-1',
      role: 'USER',
    });
    prisma.warranty.upsert.mockResolvedValue({
      id: 'warranty-1',
      imageLinks: null,
      createdBy: { storeId: 'store-1' },
    });
    privateMediaService.saveImages.mockResolvedValue(links);
    prisma.warranty.update.mockRejectedValue(new Error('database unavailable'));

    await expect(
      service.saveWarrantyImages('CP01-J12345678', [], 'user-1'),
    ).rejects.toThrow('database unavailable');
    expect(privateMediaService.discardUrls).toHaveBeenCalledWith(links);
  });

  it('rejects unsafe receipt values before database access', async () => {
    await expect(
      service.saveWarrantyImages('../outside', [], 'user-1'),
    ).rejects.toThrow('Mã biên nhận không hợp lệ');
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });

  it('rejects a non-array warranty image value before database access', async () => {
    await expect(
      service.saveWarrantyImages(
        'CP01-J12345678',
        'not-an-array' as any,
        'user-1',
      ),
    ).rejects.toThrow('Danh sách ảnh tải lên không hợp lệ');
    expect(prisma.user.findUnique).not.toHaveBeenCalled();
  });
});
