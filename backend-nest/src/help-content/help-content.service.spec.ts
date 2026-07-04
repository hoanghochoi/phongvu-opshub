import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { HelpContentService } from './help-content.service';

describe('HelpContentService', () => {
  function createHarness() {
    const prisma = {
      helpContentPage: {
        count: jest.fn().mockResolvedValue(0),
        createMany: jest.fn().mockResolvedValue({ count: 3 }),
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'page-guide',
            key: 'guide',
            title: 'Hướng dẫn sử dụng',
            fileName: 'index.md',
            parentKey: null,
            sortOrder: 0,
            markdown: '# Guide',
            isPublished: true,
            updatedByUserId: null,
            updatedByEmail: null,
            seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
            createdAt: new Date('2026-07-04T10:00:00.000Z'),
            updatedAt: new Date('2026-07-04T10:00:00.000Z'),
          },
          {
            id: 'page-getting-started',
            key: 'getting-started',
            title: 'Bắt đầu sử dụng',
            fileName: 'getting-started.md',
            parentKey: 'guide',
            sortOrder: 0,
            markdown: '# Getting started',
            isPublished: true,
            updatedByUserId: null,
            updatedByEmail: null,
            seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
            createdAt: new Date('2026-07-04T10:00:00.000Z'),
            updatedAt: new Date('2026-07-04T10:00:00.000Z'),
          },
          {
            id: 'page-roadmap',
            key: 'roadmap',
            title: 'Roadmap',
            fileName: 'roadmap.md',
            parentKey: null,
            sortOrder: 1,
            markdown: '# Roadmap',
            isPublished: true,
            updatedByUserId: null,
            updatedByEmail: null,
            seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
            createdAt: new Date('2026-07-04T10:00:00.000Z'),
            updatedAt: new Date('2026-07-04T10:00:00.000Z'),
          },
        ]),
        findUnique: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
        deleteMany: jest.fn().mockResolvedValue({ count: 3 }),
      },
      $transaction: jest.fn(async (input: any) => Promise.all(input)),
    };
    const docsLoader = {
      loadPages: jest.fn().mockResolvedValue({
        sourcePath: 'C:/repo/docs/help',
        pages: [
          {
            key: 'guide',
            title: 'Hướng dẫn sử dụng',
            fileName: 'index.md',
            parentKey: null,
            sortOrder: 0,
            markdown: '# Guide',
            isPublished: true,
          },
          {
            key: 'getting-started',
            title: 'Bắt đầu sử dụng',
            fileName: 'getting-started.md',
            parentKey: 'guide',
            sortOrder: 0,
            markdown: '# Getting started',
            isPublished: true,
          },
          {
            key: 'roadmap',
            title: 'Roadmap',
            fileName: 'roadmap.md',
            parentKey: null,
            sortOrder: 1,
            markdown: '# Roadmap',
            isPublished: true,
          },
        ],
      }),
    };
    const uploadService = {
      saveHelpContentImage: jest
        .fn()
        .mockResolvedValue(
          'https://opshub.example/uploads/help-content/guide/guide-123.png',
        ),
    };
    const service = new HelpContentService(
      prisma as any,
      docsLoader as any,
      uploadService as any,
    );
    return { prisma, docsLoader, uploadService, service };
  }

  it('seeds docs on first public load and returns runtime navigation', async () => {
    const { service, prisma, docsLoader } = createHarness();
    prisma.helpContentPage.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([
        {
          id: 'page-guide',
          key: 'guide',
          title: 'Hướng dẫn sử dụng',
          fileName: 'index.md',
          parentKey: null,
          sortOrder: 0,
          markdown: '# Guide',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:00:00.000Z'),
        },
        {
          id: 'page-getting-started',
          key: 'getting-started',
          title: 'Bắt đầu sử dụng',
          fileName: 'getting-started.md',
          parentKey: 'guide',
          sortOrder: 0,
          markdown: '# Getting started',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:00:00.000Z'),
        },
        {
          id: 'page-roadmap',
          key: 'roadmap',
          title: 'Roadmap',
          fileName: 'roadmap.md',
          parentKey: null,
          sortOrder: 1,
          markdown: '# Roadmap',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:00:00.000Z'),
        },
      ]);

    await expect(service.getPublicContent()).resolves.toMatchObject({
      source: 'runtime',
      pages: expect.arrayContaining([
        expect.objectContaining({ key: 'guide', title: 'Hướng dẫn sử dụng' }),
        expect.objectContaining({
          key: 'getting-started',
          parentKey: 'guide',
        }),
      ]),
      navigation: expect.arrayContaining([
        expect.objectContaining({
          key: 'guide',
          children: expect.arrayContaining([
            expect.objectContaining({ key: 'getting-started' }),
          ]),
        }),
      ]),
    });

    expect(docsLoader.loadPages).toHaveBeenCalledTimes(1);
    expect(prisma.helpContentPage.createMany).toHaveBeenCalled();
  });

  it('only includes private help pages after authentication', async () => {
    const { service, prisma } = createHarness();
    const pages = [
      {
        id: 'page-guide',
        key: 'guide',
        title: 'Hướng dẫn sử dụng',
        fileName: 'index.md',
        parentKey: null,
        sortOrder: 0,
        markdown: '# Guide',
        isPublished: true,
        isAuthenticatedOnly: false,
        updatedByUserId: null,
        updatedByEmail: null,
        seededFromDocsAt: null,
        createdAt: new Date('2026-07-04T10:00:00.000Z'),
        updatedAt: new Date('2026-07-04T10:00:00.000Z'),
      },
      {
        id: 'page-internal',
        key: 'internal',
        title: 'Quy trình nội bộ',
        fileName: 'internal.md',
        parentKey: null,
        sortOrder: 1,
        markdown: '# Internal',
        isPublished: true,
        isAuthenticatedOnly: true,
        updatedByUserId: null,
        updatedByEmail: null,
        seededFromDocsAt: null,
        createdAt: new Date('2026-07-04T10:00:00.000Z'),
        updatedAt: new Date('2026-07-04T10:00:00.000Z'),
      },
    ];

    prisma.helpContentPage.findMany
      .mockResolvedValueOnce(pages)
      .mockResolvedValueOnce([pages[0]]);
    await service.getPublicContent();
    expect(prisma.helpContentPage.findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: { isPublished: true, isAuthenticatedOnly: false },
      }),
    );

    prisma.helpContentPage.findMany.mockReset();
    prisma.helpContentPage.findMany
      .mockResolvedValueOnce(pages)
      .mockResolvedValueOnce(pages);
    await service.getPublicContent({ id: 'user-1' });
    expect(prisma.helpContentPage.findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: { isPublished: true },
      }),
    );
  });

  it('blocks admin help access for non-super-admin users', async () => {
    const { service, prisma } = createHarness();

    await expect(
      service.getAdminPages({ id: 'user-1', role: 'ADMIN_PHONGVU' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.helpContentPage.findMany).not.toHaveBeenCalled();
  });

  it('updates an existing help page and stamps updater identity', async () => {
    const { service, prisma } = createHarness();
    prisma.helpContentPage.count.mockResolvedValue(3);
    prisma.helpContentPage.findUnique.mockResolvedValue({
      id: 'page-roadmap',
      key: 'roadmap',
      title: 'Roadmap',
      fileName: 'roadmap.md',
      parentKey: null,
      sortOrder: 1,
      markdown: '# Roadmap',
      isPublished: true,
      updatedByUserId: null,
      updatedByEmail: null,
      seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
      createdAt: new Date('2026-07-04T10:00:00.000Z'),
      updatedAt: new Date('2026-07-04T10:00:00.000Z'),
    });
    prisma.helpContentPage.update.mockResolvedValue({
      id: 'page-roadmap',
      key: 'roadmap',
      title: 'Roadmap quý 3',
      fileName: 'roadmap.md',
      parentKey: null,
      sortOrder: 3,
      markdown: '# Roadmap mới',
      isPublished: true,
      updatedByUserId: 'admin-1',
      updatedByEmail: 'admin@phongvu.vn',
      seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
      createdAt: new Date('2026-07-04T10:00:00.000Z'),
      updatedAt: new Date('2026-07-04T10:05:00.000Z'),
    });

    await expect(
      service.updatePage(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        'roadmap',
        {
          title: 'Roadmap quý 3',
          sortOrder: 3,
          markdown: '# Roadmap mới',
        },
      ),
    ).resolves.toMatchObject({
      key: 'roadmap',
      title: 'Roadmap quý 3',
      updatedByEmail: 'admin@phongvu.vn',
    });

    expect(prisma.helpContentPage.update).toHaveBeenCalledWith({
      where: { key: 'roadmap' },
      data: expect.objectContaining({
        title: 'Roadmap quý 3',
        sortOrder: 3,
        markdown: '# Roadmap mới',
        updatedByUserId: 'admin-1',
        updatedByEmail: 'admin@phongvu.vn',
        seededFromDocsAt: null,
      }),
    });
  });

  it('auto-syncs docs-managed runtime pages when docs content changes', async () => {
    const { service, prisma, docsLoader } = createHarness();
    prisma.helpContentPage.count.mockResolvedValue(3);
    prisma.helpContentPage.findMany
      .mockResolvedValueOnce([
        {
          id: 'page-guide',
          key: 'guide',
          title: 'Hướng dẫn sử dụng',
          fileName: 'index.md',
          parentKey: null,
          sortOrder: 0,
          markdown: '# Guide cũ',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:00:00.000Z'),
        },
        {
          id: 'page-roadmap',
          key: 'roadmap',
          title: 'Roadmap',
          fileName: 'roadmap.md',
          parentKey: null,
          sortOrder: 1,
          markdown: '# Roadmap',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:00:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:00:00.000Z'),
        },
      ])
      .mockResolvedValueOnce([
        {
          id: 'page-guide',
          key: 'guide',
          title: 'Hướng dẫn sử dụng',
          fileName: 'index.md',
          parentKey: null,
          sortOrder: 0,
          markdown: '# Guide mới',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:10:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:10:00.000Z'),
        },
        {
          id: 'page-roadmap',
          key: 'roadmap',
          title: 'Roadmap',
          fileName: 'roadmap.md',
          parentKey: null,
          sortOrder: 1,
          markdown: '# Roadmap',
          isPublished: true,
          updatedByUserId: null,
          updatedByEmail: null,
          seededFromDocsAt: new Date('2026-07-04T10:10:00.000Z'),
          createdAt: new Date('2026-07-04T10:00:00.000Z'),
          updatedAt: new Date('2026-07-04T10:10:00.000Z'),
        },
      ]);
    docsLoader.loadPages.mockResolvedValueOnce({
      sourcePath: 'C:/repo/docs/help',
      pages: [
        {
          key: 'guide',
          title: 'Hướng dẫn sử dụng',
          fileName: 'index.md',
          parentKey: null,
          sortOrder: 0,
          markdown: '# Guide mới',
          isPublished: true,
        },
        {
          key: 'roadmap',
          title: 'Roadmap',
          fileName: 'roadmap.md',
          parentKey: null,
          sortOrder: 1,
          markdown: '# Roadmap',
          isPublished: true,
        },
      ],
    });

    await expect(service.getPublicContent()).resolves.toMatchObject({
      pages: expect.arrayContaining([
        expect.objectContaining({ key: 'guide', markdown: '# Guide mới' }),
      ]),
    });

    expect(prisma.helpContentPage.deleteMany).toHaveBeenCalledWith({});
    expect(prisma.helpContentPage.createMany).toHaveBeenCalledWith({
      data: expect.arrayContaining([
        expect.objectContaining({ key: 'guide', markdown: '# Guide mới' }),
      ]),
    });
  });

  it('throws not found when updating a missing help page', async () => {
    const { service, prisma } = createHarness();
    prisma.helpContentPage.findUnique.mockResolvedValue(null);

    await expect(
      service.updatePage({ id: 'admin-1', role: 'SUPER_ADMIN' }, 'missing', {
        title: 'Không có',
      }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it('replaces runtime pages from docs when restore requests overwrite', async () => {
    const { service, prisma } = createHarness();
    prisma.helpContentPage.count.mockResolvedValue(3);

    await expect(
      service.seedFromDocs(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        { overwriteExisting: true },
      ),
    ).resolves.toMatchObject({
      seeded: true,
      overwriteExisting: true,
      pageCount: 3,
      sourcePath: 'C:/repo/docs/help',
    });

    expect(prisma.$transaction).toHaveBeenCalled();
    expect(prisma.helpContentPage.deleteMany).toHaveBeenCalledWith({});
  });

  it('uploads a help image for super admin and returns a markdown snippet', async () => {
    const { service, uploadService } = createHarness();

    await expect(
      service.uploadAsset(
        { id: 'admin-1', email: 'admin@phongvu.vn', role: 'SUPER_ADMIN' },
        { pageKey: 'guide' },
        {
          originalname: 'setup.png',
          size: 1024,
          buffer: Buffer.from([1, 2, 3]),
        } as any,
      ),
    ).resolves.toMatchObject({
      pageKey: 'guide',
      imageUrl:
        'https://opshub.example/uploads/help-content/guide/guide-123.png',
      markdown:
        '![Mô tả ảnh](https://opshub.example/uploads/help-content/guide/guide-123.png)',
      fileName: 'setup.png',
    });

    expect(uploadService.saveHelpContentImage).toHaveBeenCalledWith(
      'guide',
      expect.objectContaining({ originalname: 'setup.png', size: 1024 }),
    );
  });
});
