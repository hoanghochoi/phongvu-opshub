import { copyFile, cp, mkdir, readFile, readdir, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const rootDir = process.cwd();
const templatePath = path.join(rootDir, 'deploy', 'home-server', 'help.html');
const helpSourceDir = path.join(rootDir, 'docs', 'help');
const navigationPath = path.join(helpSourceDir, 'navigation.json');
const contentDir = path.join(rootDir, 'docs', 'help', 'content');
const assetsDir = path.join(rootDir, 'docs', 'help', 'assets');
const outputDir = path.join(rootDir, 'dist', 'help');

async function main() {
  const navigation = await readNavigation();
  const pages = flattenNavigation(navigation);
  await ensureRequiredSources(pages);
  await rm(outputDir, { recursive: true, force: true });
  await mkdir(path.join(outputDir, 'content'), { recursive: true });
  await copyFile(templatePath, path.join(outputDir, 'index.html'));
  await copyFile(navigationPath, path.join(outputDir, 'navigation.json'));

  for (const { file } of pages) {
    await copyFile(
      path.join(contentDir, file),
      path.join(outputDir, 'content', file),
    );
  }

  if (await exists(assetsDir)) {
    await cp(assetsDir, path.join(outputDir, 'assets'), {
      recursive: true,
      force: true,
    });
  }

  await validateMarkdownAssetReferences();
  console.log(`Built help site at ${path.relative(rootDir, outputDir)}`);
}

async function readNavigation() {
  await assertFile(navigationPath);
  const raw = await readFile(navigationPath, 'utf8');
  const navigation = JSON.parse(raw);
  if (!Array.isArray(navigation) || navigation.length === 0) {
    throw new Error('docs/help/navigation.json must contain at least one page');
  }
  return navigation;
}

function flattenNavigation(items, parentKey = '') {
  const pages = [];
  const seenKeys = new Set();
  const seenFiles = new Set();

  function visit(item, parent) {
    if (!item || typeof item !== 'object') {
      throw new Error('Every help navigation item must be an object');
    }
    const key = requireCleanString(item.key, 'key');
    const title = requireCleanString(item.title, 'title');
    const file = requireCleanString(item.file, 'file');
    if (!/^[a-z0-9-]+$/.test(key)) {
      throw new Error(`Help navigation key must use lowercase letters, numbers, or hyphens: ${key}`);
    }
    if (!/^[a-z0-9-]+\.md$/.test(file)) {
      throw new Error(`Help content file must be a simple kebab-case Markdown file name: ${file}`);
    }
    if (seenKeys.has(key)) throw new Error(`Duplicate help navigation key: ${key}`);
    seenKeys.add(key);
    seenFiles.add(file);
    pages.push({ key, title, file, parentKey: parent });

    const children = item.children ?? [];
    if (!Array.isArray(children)) {
      throw new Error(`children must be an array for help page: ${key}`);
    }
    for (const child of children) {
      visit(child, key);
    }
  }

  for (const item of items) {
    visit(item, parentKey);
  }

  if (!seenKeys.has('guide')) {
    throw new Error('Help navigation must include a guide page');
  }
  if (!seenKeys.has('roadmap')) {
    throw new Error('Help navigation must include a roadmap page');
  }
  if (seenFiles.size !== pages.length) {
    throw new Error('Each help navigation page should use its own Markdown file');
  }
  return pages;
}

function requireCleanString(value, name) {
  if (typeof value !== 'string' || value.trim() !== value || value.length === 0) {
    throw new Error(`Help navigation ${name} must be a non-empty trimmed string`);
  }
  return value;
}

async function ensureRequiredSources(pages) {
  await assertFile(templatePath);
  for (const { file } of pages) {
    await assertFile(path.join(contentDir, file));
  }
}

async function validateMarkdownAssetReferences() {
  const markdownFiles = await readdir(contentDir);
  const missingAssets = [];

  for (const fileName of markdownFiles.filter((name) => name.endsWith('.md'))) {
    const markdown = await readFile(path.join(contentDir, fileName), 'utf8');
    const markdownWithoutCode = markdown.replace(/```[\s\S]*?```/g, '');
    const references = [
      ...markdownWithoutCode.matchAll(/!\[[^\]]*]\(([^)]+)\)/g),
    ].map((match) => match[1].trim());
    for (const reference of references) {
      if (
        reference.startsWith('http://') ||
        reference.startsWith('https://') ||
        reference.startsWith('/')
      ) {
        continue;
      }
      const target = reference.startsWith('assets/')
        ? path.join(helpSourceDir, reference)
        : path.join(contentDir, reference);
      if (!(await exists(target))) {
        missingAssets.push(`${fileName}: ${reference}`);
      }
    }
  }

  if (missingAssets.length > 0) {
    throw new Error(
      `Missing help image assets:\n${missingAssets
        .map((item) => `- ${item}`)
        .join('\n')}`,
    );
  }
}

async function assertFile(filePath) {
  const fileStat = await stat(filePath).catch(() => null);
  if (!fileStat?.isFile()) {
    throw new Error(`Required file is missing: ${path.relative(rootDir, filePath)}`);
  }
}

async function exists(filePath) {
  return stat(filePath)
    .then(() => true)
    .catch(() => false);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
