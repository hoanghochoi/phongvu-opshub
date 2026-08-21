import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const helper = path.join(repositoryRoot, 'scripts', 'verify-help-content-sentinel.mjs');
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-help-sentinel-'));

function run(...args) {
  execFileSync(process.execPath, [helper, ...args], { stdio: 'pipe' });
}

function response(page) {
  return `${JSON.stringify({ pages: [page] })}\n`;
}

function digest(value) {
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function canonicalPages(pages) {
  return pages
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

function writeState(file, publicPages, editorKeys = []) {
  publicPages = canonicalPages(publicPages);
  const publicKeys = new Set(publicPages.map((page) => page.key));
  const editorPublicCount = editorKeys.filter((key) => publicKeys.has(key)).length;
  const hiddenEditorCount = editorKeys.length - editorPublicCount;
  fs.writeFileSync(
    file,
    `${JSON.stringify({
      schemaVersion: 1,
      pageCount: publicPages.length + hiddenEditorCount,
      docsManagedCount: publicPages.length - editorPublicCount,
      editorManagedCount: editorKeys.length,
      editorOwnershipSha256: digest([...editorKeys].sort()),
      publicProjectionSha256: digest(publicPages),
    })}\n`,
  );
}

try {
  const docs = path.join(temporaryRoot, 'docs');
  fs.mkdirSync(path.join(docs, 'content'), { recursive: true });
  fs.writeFileSync(
    path.join(docs, 'navigation.json'),
    `${JSON.stringify([{ key: 'guide', title: 'Hướng dẫn mới', file: 'guide.md' }])}\n`,
  );
  fs.writeFileSync(path.join(docs, 'content', 'guide.md'), '# Sentinel mới\n');
  const docsSentinel = path.join(temporaryRoot, 'docs-sentinel.json');
  run('from-docs', docs, docsSentinel);

  const common = {
    key: 'guide',
    fileName: 'guide.md',
    parentKey: null,
    sortOrder: 0,
    isPublished: true,
    isAuthenticatedOnly: false,
  };
  const docsManagedBefore = path.join(temporaryRoot, 'docs-managed-before.json');
  const docsManagedAfter = path.join(temporaryRoot, 'docs-managed-after.json');
  fs.writeFileSync(
    docsManagedBefore,
    response({
      ...common,
      title: 'Hướng dẫn cũ',
      markdown: '# Sentinel cũ\n',
      seededFromDocsAt: '2026-08-20T00:00:00.000Z',
    }),
  );
  fs.writeFileSync(
    docsManagedAfter,
    response({
      ...common,
      title: 'Hướng dẫn mới',
      markdown: '# Sentinel mới\n',
      seededFromDocsAt: '2026-08-22T00:00:00.000Z',
    }),
  );
  const docsBeforeState = path.join(temporaryRoot, 'docs-before-state.json');
  const docsAfterState = path.join(temporaryRoot, 'docs-after-state.json');
  const docsBeforePage = JSON.parse(fs.readFileSync(docsManagedBefore, 'utf8')).pages[0];
  const docsAfterPage = JSON.parse(fs.readFileSync(docsManagedAfter, 'utf8')).pages[0];
  const normalizedDocsBefore = [{ ...docsBeforePage }];
  const normalizedDocsAfter = [{ ...docsAfterPage }];
  delete normalizedDocsBefore[0].seededFromDocsAt;
  delete normalizedDocsAfter[0].seededFromDocsAt;
  writeState(docsBeforeState, normalizedDocsBefore);
  writeState(docsAfterState, normalizedDocsAfter);
  run(
    'verify-static-response',
    docsBeforeState,
    docsSentinel,
    docsAfterState,
    docsManagedAfter,
  );

  const editorBefore = path.join(temporaryRoot, 'editor-before.json');
  const editorAfter = path.join(temporaryRoot, 'editor-after.json');
  fs.writeFileSync(
    editorBefore,
    response({
      ...common,
      title: 'Nội dung biên tập',
      markdown: '# Giữ chỉnh sửa runtime\n',
      seededFromDocsAt: null,
    }),
  );
  fs.copyFileSync(editorBefore, editorAfter);
  const editorPage = JSON.parse(fs.readFileSync(editorAfter, 'utf8')).pages[0];
  delete editorPage.seededFromDocsAt;
  const editorBeforeState = path.join(temporaryRoot, 'editor-before-state.json');
  const editorAfterState = path.join(temporaryRoot, 'editor-after-state.json');
  writeState(editorBeforeState, [editorPage], ['guide']);
  writeState(editorAfterState, [editorPage], ['guide']);
  run(
    'verify-static-response',
    editorBeforeState,
    docsSentinel,
    editorAfterState,
    editorAfter,
  );

  let editorOverwriteRejected = false;
  try {
    run(
      'verify-static-response',
      editorBeforeState,
      docsSentinel,
      docsAfterState,
      docsManagedAfter,
    );
  } catch {
    editorOverwriteRejected = true;
  }
  if (!editorOverwriteRejected) {
    throw new Error('editor-managed Help was overwritten by the docs sentinel');
  }

  const editorSentinel = path.join(temporaryRoot, 'editor-sentinel.json');
  run('from-response', editorBefore, editorSentinel);
  run('verify-response', editorSentinel, editorAfter);

  for (const visibility of ['draft', 'private']) {
    const hiddenBeforeState = path.join(
      temporaryRoot,
      `hidden-${visibility}-before-state.json`,
    );
    const hiddenAfterState = path.join(
      temporaryRoot,
      `hidden-${visibility}-after-state.json`,
    );
    writeState(hiddenBeforeState, normalizedDocsBefore, [`hidden-${visibility}`]);
    writeState(hiddenAfterState, normalizedDocsBefore, [`hidden-${visibility}`]);
    run(
      'verify-static-response',
      hiddenBeforeState,
      docsSentinel,
      hiddenAfterState,
      docsManagedBefore,
    );
  }

  const concurrentResponse = path.join(temporaryRoot, 'concurrent-editor.json');
  const concurrentPage = {
    ...normalizedDocsBefore[0],
    markdown: '# Cập nhật hợp lệ trong lúc deploy\n',
  };
  fs.writeFileSync(concurrentResponse, response(concurrentPage));
  const concurrentState = path.join(temporaryRoot, 'concurrent-state.json');
  writeState(concurrentState, [concurrentPage], ['guide']);
  run(
    'verify-static-response',
    docsBeforeState,
    docsSentinel,
    concurrentState,
    concurrentResponse,
  );
  console.log('Help content docs-managed refresh and editor-managed preservation sentinel PASS');
} finally {
  fs.rmSync(temporaryRoot, { force: true, recursive: true });
}
