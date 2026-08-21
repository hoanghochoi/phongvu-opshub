import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';
import type { HelpContentPage } from '@prisma/client';
import { createHash } from 'crypto';
import pg from 'pg';

type DeployStatePage = Pick<
  HelpContentPage,
  | 'key'
  | 'title'
  | 'fileName'
  | 'parentKey'
  | 'sortOrder'
  | 'markdown'
  | 'isPublished'
  | 'isAuthenticatedOnly'
  | 'seededFromDocsAt'
>;

function digest(value: unknown) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function publicProjection(pages: DeployStatePage[]) {
  return pages
    .filter((page) => page.isPublished && !page.isAuthenticatedOnly)
    .map((page) => ({
      key: page.key,
      title: page.title,
      fileName: page.fileName,
      parentKey: page.parentKey,
      sortOrder: page.sortOrder,
      markdown: page.markdown,
      isPublished: page.isPublished,
      isAuthenticatedOnly: page.isAuthenticatedOnly,
    }))
    .sort((left, right) => left.key.localeCompare(right.key));
}

export function buildHelpContentDeployState(pages: DeployStatePage[]) {
  const editorManagedKeys = pages
    .filter((page) => page.seededFromDocsAt == null)
    .map((page) => page.key)
    .sort();
  const docsManagedCount = pages.length - editorManagedKeys.length;
  return {
    schemaVersion: 1,
    pageCount: pages.length,
    docsManagedCount,
    editorManagedCount: editorManagedKeys.length,
    editorOwnershipSha256: digest(editorManagedKeys),
    publicProjectionSha256: digest(publicProjection(pages)),
  };
}

export async function runHelpContentDeployStateProbe() {
  const connectionString = process.env.DATABASE_URL?.trim();
  if (!connectionString) {
    throw new Error(
      'DATABASE_URL is required for the Help content deploy-state probe',
    );
  }

  const pool = new pg.Pool({ connectionString });
  let prisma: PrismaClient | undefined;
  try {
    const adapter = new PrismaPg(pool);
    prisma = new PrismaClient({ adapter });
    const pages = await prisma.helpContentPage.findMany({
      orderBy: [{ key: 'asc' }],
    });
    return buildHelpContentDeployState(pages);
  } finally {
    try {
      await prisma?.$disconnect();
    } finally {
      await pool.end();
    }
  }
}

if (require.main === module) {
  void runHelpContentDeployStateProbe()
    .then((state) => {
      process.stdout.write(`${JSON.stringify(state)}\n`);
    })
    .catch((error) => {
      const message = error instanceof Error ? error.message : 'unknown error';
      process.stderr.write(
        `Help content deploy-state probe failed: ${message}\n`,
      );
      process.exitCode = 1;
    });
}
