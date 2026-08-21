import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function fail(message) {
  console.error(`Help content sentinel: ${message}`);
  process.exit(1);
}

function requiredText(value, field) {
  const text = String(value ?? '').trim();
  if (!text) fail(`missing ${field}`);
  return text;
}

function normalizedPages(pages) {
  if (!Array.isArray(pages) || pages.length === 0) fail('page list is empty');
  return pages
    .map((page) => ({
      key: requiredText(page.key, 'key'),
      title: requiredText(page.title, 'title'),
      fileName: requiredText(page.fileName, 'fileName'),
      parentKey: page.parentKey == null ? null : requiredText(page.parentKey, 'parentKey'),
      sortOrder: Number(page.sortOrder),
      markdown: String(page.markdown ?? ''),
      isPublished: page.isPublished === true,
      isAuthenticatedOnly: page.isAuthenticatedOnly === true,
    }))
    .sort((left, right) => left.key.localeCompare(right.key));
}

function pagesFromDocs(docsDirectory) {
  const navigationPath = path.join(docsDirectory, 'navigation.json');
  const contentDirectory = path.join(docsDirectory, 'content');
  const navigation = JSON.parse(fs.readFileSync(navigationPath, 'utf8'));
  const pages = [];

  function append(nodes, parentKey = null) {
    if (!Array.isArray(nodes)) fail('navigation root or children is not an array');
    nodes.forEach((node, sortOrder) => {
      const key = requiredText(node.key, 'navigation key');
      const title = requiredText(node.title, `title for ${key}`);
      const fileName = requiredText(node.file, `file for ${key}`);
      if (path.basename(fileName) !== fileName) fail(`unsafe file name for ${key}`);
      pages.push({
        key,
        title,
        fileName,
        parentKey,
        sortOrder,
        markdown: fs.readFileSync(path.join(contentDirectory, fileName), 'utf8'),
        isPublished: true,
        isAuthenticatedOnly: false,
      });
      if (node.children != null) append(node.children, key);
    });
  }

  append(navigation);
  return normalizedPages(pages);
}

function pagesFromResponse(responsePath) {
  const payload = JSON.parse(fs.readFileSync(responsePath, 'utf8'));
  return normalizedPages(payload.pages);
}

function writeSentinel(outputPath, pages) {
  const payload = `${JSON.stringify({ schemaVersion: 1, pages }, null, 2)}\n`;
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, payload, 'utf8');
  const digest = crypto.createHash('sha256').update(payload).digest('hex');
  console.log(`Help content sentinel recorded: pages=${pages.length} sha256=${digest}`);
}

function readSentinel(sentinelPath) {
  const sentinel = JSON.parse(fs.readFileSync(sentinelPath, 'utf8'));
  if (sentinel.schemaVersion !== 1) fail('unsupported sentinel schema');
  return normalizedPages(sentinel.pages);
}

function readDeployState(statePath) {
  const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  for (const field of ['pageCount', 'docsManagedCount', 'editorManagedCount']) {
    if (!Number.isInteger(state[field]) || state[field] < 0) {
      fail(`deploy state has invalid ${field}`);
    }
  }
  for (const field of ['editorOwnershipSha256', 'publicProjectionSha256']) {
    if (!/^[a-f0-9]{64}$/.test(String(state[field] ?? ''))) {
      fail(`deploy state has invalid ${field}`);
    }
  }
  if (
    state.schemaVersion !== 1 ||
    state.docsManagedCount + state.editorManagedCount !== state.pageCount
  ) {
    fail('deploy state schema or ownership counts are inconsistent');
  }
  return state;
}

function projectionDigest(pages) {
  return crypto
    .createHash('sha256')
    .update(JSON.stringify(pages))
    .digest('hex');
}

const [command, ...args] = process.argv.slice(2);
switch (command) {
  case 'from-docs': {
    const [inputPath, outputPath] = args;
    if (!inputPath || !outputPath) fail('usage: from-docs <docs-dir> <output>');
    writeSentinel(outputPath, pagesFromDocs(inputPath));
    break;
  }
  case 'from-response': {
    const [inputPath, outputPath] = args;
    if (!inputPath || !outputPath) fail('usage: from-response <response> <output>');
    writeSentinel(outputPath, pagesFromResponse(inputPath));
    break;
  }
  case 'verify-response': {
    const [sentinelPath, responsePath] = args;
    if (!sentinelPath || !responsePath) fail('usage: verify-response <sentinel> <response>');
    const expected = readSentinel(sentinelPath);
    const actual = pagesFromResponse(responsePath);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      fail(`response differs from sentinel: expectedPages=${expected.length} actualPages=${actual.length}`);
    }
    console.log(`Help content response matches sentinel: pages=${actual.length}`);
    break;
  }
  case 'verify-static-response': {
    const [beforeStatePath, docsSentinelPath, afterStatePath, afterResponsePath] =
      args;
    if (
      !beforeStatePath ||
      !docsSentinelPath ||
      !afterStatePath ||
      !afterResponsePath
    ) {
      fail('usage: verify-static-response <before-state> <docs-sentinel> <after-state> <after-response>');
    }
    const beforeState = readDeployState(beforeStatePath);
    const afterState = readDeployState(afterStatePath);
    const actual = pagesFromResponse(afterResponsePath);
    if (projectionDigest(actual) !== afterState.publicProjectionSha256) {
      fail(
        `public response differs from full server-side state: actualPages=${actual.length}`,
      );
    }
    if (
      beforeState.editorManagedCount > 0 &&
      afterState.editorManagedCount === 0
    ) {
      fail('editor-managed ownership disappeared during static publication');
    }
    if (afterState.editorManagedCount > 0) {
      console.log(
        `Help content static response verified: mode=editor-managed-preserved pages=${actual.length} editorManagedCount=${afterState.editorManagedCount}`,
      );
      break;
    }
    const expected = readSentinel(docsSentinelPath);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
      fail(
        `docs-managed response differs from deployed Help bundle: expectedPages=${expected.length} actualPages=${actual.length}`,
      );
    }
    console.log(
      `Help content static response verified: mode=docs-managed-refresh pages=${actual.length}`,
    );
    break;
  }
  default:
    fail('supported commands: from-docs, from-response, verify-response, verify-static-response');
}
