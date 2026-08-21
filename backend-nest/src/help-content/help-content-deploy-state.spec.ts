jest.mock('@prisma/adapter-pg', () => ({ PrismaPg: jest.fn() }));
jest.mock('@prisma/client', () => ({ PrismaClient: jest.fn() }));
jest.mock('pg', () => ({
  __esModule: true,
  default: { Pool: jest.fn() },
}));

import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import pg from 'pg';
import {
  buildHelpContentDeployState,
  runHelpContentDeployStateProbe,
} from './help-content-deploy-state';

const prismaPgConstructor = PrismaPg as unknown as jest.Mock;
const prismaClientConstructor = PrismaClient as unknown as jest.Mock;
const poolConstructor = pg.Pool as unknown as jest.Mock;

function page(overrides: Record<string, unknown> = {}) {
  return {
    key: 'guide',
    title: 'Hướng dẫn',
    fileName: 'guide.md',
    parentKey: null,
    sortOrder: 0,
    markdown: '# Hướng dẫn',
    isPublished: true,
    isAuthenticatedOnly: false,
    seededFromDocsAt: new Date('2026-08-22T00:00:00.000Z'),
    ...overrides,
  } as any;
}

describe('buildHelpContentDeployState', () => {
  it.each([
    ['draft', { key: 'draft', isPublished: false }],
    ['private', { key: 'private', isAuthenticatedOnly: true }],
  ])('detects a hidden editor-managed %s page', (_label, overrides) => {
    const state = buildHelpContentDeployState([
      page(),
      page({ ...overrides, seededFromDocsAt: null }),
    ]);

    expect(state).toMatchObject({
      pageCount: 2,
      docsManagedCount: 1,
      editorManagedCount: 1,
    });
  });

  it('changes the public projection when a concurrent editor update is visible', () => {
    const before = buildHelpContentDeployState([page()]);
    const after = buildHelpContentDeployState([
      page({ markdown: '# Editor update', seededFromDocsAt: null }),
    ]);

    expect(after.editorManagedCount).toBe(1);
    expect(after.publicProjectionSha256).not.toBe(
      before.publicProjectionSha256,
    );
  });
});

describe('runHelpContentDeployStateProbe', () => {
  const originalDatabaseUrl = process.env.DATABASE_URL;

  afterAll(() => {
    if (originalDatabaseUrl === undefined) {
      delete process.env.DATABASE_URL;
    } else {
      process.env.DATABASE_URL = originalDatabaseUrl;
    }
  });

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.DATABASE_URL = 'postgresql://probe.example/opshub';
  });

  it('constructs the Prisma 7 pg adapter and closes both resources', async () => {
    const pool = { end: jest.fn().mockResolvedValue(undefined) };
    const adapter = { adapter: 'pg' };
    const prisma = {
      helpContentPage: {
        findMany: jest.fn().mockResolvedValue([page()]),
      },
      $disconnect: jest.fn().mockResolvedValue(undefined),
    };
    poolConstructor.mockImplementation(() => pool);
    prismaPgConstructor.mockImplementation(() => adapter);
    prismaClientConstructor.mockImplementation(() => prisma);

    await expect(runHelpContentDeployStateProbe()).resolves.toMatchObject({
      pageCount: 1,
      docsManagedCount: 1,
      editorManagedCount: 0,
    });

    expect(poolConstructor).toHaveBeenCalledWith({
      connectionString: 'postgresql://probe.example/opshub',
    });
    expect(prismaPgConstructor).toHaveBeenCalledWith(pool);
    expect(prismaClientConstructor).toHaveBeenCalledWith({ adapter });
    expect(prisma.helpContentPage.findMany).toHaveBeenCalledWith({
      orderBy: [{ key: 'asc' }],
    });
    expect(prisma.$disconnect).toHaveBeenCalledTimes(1);
    expect(pool.end).toHaveBeenCalledTimes(1);
  });

  it('still disconnects Prisma and ends the pool when the query fails', async () => {
    const queryError = new Error('query failed');
    const pool = { end: jest.fn().mockResolvedValue(undefined) };
    const prisma = {
      helpContentPage: {
        findMany: jest.fn().mockRejectedValue(queryError),
      },
      $disconnect: jest.fn().mockResolvedValue(undefined),
    };
    poolConstructor.mockImplementation(() => pool);
    prismaPgConstructor.mockImplementation(() => ({ adapter: 'pg' }));
    prismaClientConstructor.mockImplementation(() => prisma);

    await expect(runHelpContentDeployStateProbe()).rejects.toBe(queryError);
    expect(prisma.$disconnect).toHaveBeenCalledTimes(1);
    expect(pool.end).toHaveBeenCalledTimes(1);
  });

  it('fails before allocating resources when DATABASE_URL is absent', async () => {
    delete process.env.DATABASE_URL;

    await expect(runHelpContentDeployStateProbe()).rejects.toThrow(
      'DATABASE_URL is required',
    );
    expect(poolConstructor).not.toHaveBeenCalled();
    expect(prismaPgConstructor).not.toHaveBeenCalled();
    expect(prismaClientConstructor).not.toHaveBeenCalled();
  });
});
