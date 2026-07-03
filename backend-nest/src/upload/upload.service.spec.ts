import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
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

  it('saves multiple warranty images under the same receipt', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-upload-'));
    const previousBaseDir = process.env.UPLOAD_BASE_DIR;
    const previousBaseUrl = process.env.IMAGE_BASE_URL;
    process.env.UPLOAD_BASE_DIR = tempDir;
    process.env.IMAGE_BASE_URL = 'https://img.example.com/uploads';
    service = new UploadService(prisma as any);

    try {
      const files = [
        {
          originalname: 'first.jpg',
          buffer: Buffer.from([1, 2, 3]),
        },
        {
          originalname: 'second.png',
          buffer: Buffer.from([4, 5, 6]),
        },
      ] as Express.Multer.File[];

      await expect(
        service.saveWarrantyImages('CP01-J12345678', files),
      ).resolves.toEqual([
        'https://img.example.com/uploads/CP01-J12345678/CP01-J12345678-0.jpg',
        'https://img.example.com/uploads/CP01-J12345678/CP01-J12345678-1.png',
      ]);

      expect(
        fs.readFileSync(
          path.join(tempDir, 'CP01-J12345678', 'CP01-J12345678-0.jpg'),
        ),
      ).toEqual(Buffer.from([1, 2, 3]));
      expect(
        fs.readFileSync(
          path.join(tempDir, 'CP01-J12345678', 'CP01-J12345678-1.png'),
        ),
      ).toEqual(Buffer.from([4, 5, 6]));
    } finally {
      if (previousBaseDir === undefined) {
        delete process.env.UPLOAD_BASE_DIR;
      } else {
        process.env.UPLOAD_BASE_DIR = previousBaseDir;
      }
      if (previousBaseUrl === undefined) {
        delete process.env.IMAGE_BASE_URL;
      } else {
        process.env.IMAGE_BASE_URL = previousBaseUrl;
      }
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
  });

  it('rejects unsafe receipt path segments', async () => {
    await expect(service.saveWarrantyImages('../outside', [])).rejects.toThrow(
      'receipt không hợp lệ',
    );
  });
});
