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
    const service = new HelpContentService(prisma as any, docsLoader as any);
    return { prisma, docsLoader, service };
  }

  it('seeds docs on first public load and returns runtime navigation', async () => {
    const { service, prisma, docsLoader } = createHarness();

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
      }),
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
});
