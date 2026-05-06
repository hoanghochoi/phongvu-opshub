import { UploadService } from './upload.service';

describe('UploadService', () => {
  let service: UploadService;
  let prisma: { warranty: { upsert: jest.Mock } };

  beforeEach(() => {
    prisma = { warranty: { upsert: jest.fn() } };
    service = new UploadService(prisma as any);
  });

  it('joins and parses semicolon-separated image links', () => {
    const links = [
      'https://img.example.com/a.jpg',
      'https://img.example.com/b.jpg',
    ];

    expect(service.getLinksString(links)).toBe(
      'https://img.example.com/a.jpg;https://img.example.com/b.jpg',
    );
    expect(service.parseLinksString('a.jpg;; b.jpg ;')).toEqual([
      'a.jpg',
      'b.jpg',
    ]);
  });

  it('upserts warranty records after image upload', async () => {
    prisma.warranty.upsert.mockResolvedValue({ id: 'warranty-1' });

    await expect(
      service.upsertWarrantyRecord(
        'CP01-J12345678',
        ['https://img.example.com/receipt/0.jpg'],
        'user-1',
      ),
    ).resolves.toEqual({ id: 'warranty-1' });

    expect(prisma.warranty.upsert).toHaveBeenCalledWith({
      where: { receipt: 'CP01-J12345678' },
      update: {
        imageLinks: 'https://img.example.com/receipt/0.jpg',
      },
      create: {
        receipt: 'CP01-J12345678',
        imageLinks: 'https://img.example.com/receipt/0.jpg',
        createdById: 'user-1',
      },
    });
  });

  it('rejects unsafe receipt path segments', async () => {
    await expect(service.saveWarrantyImages('../outside', [])).rejects.toThrow(
      'receipt không hợp lệ',
    );
  });
});
