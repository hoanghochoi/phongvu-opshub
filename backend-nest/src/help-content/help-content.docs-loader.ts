import {
  Injectable,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import { access, readFile } from 'fs/promises';
import { basename, join, resolve } from 'path';

type DocsNavigationNode = {
  key?: unknown;
  title?: unknown;
  file?: unknown;
  children?: unknown;
};

export type HelpDocsPageSeed = {
  key: string;
  title: string;
  fileName: string;
  parentKey: string | null;
  sortOrder: number;
  markdown: string;
  isPublished: boolean;
  isAuthenticatedOnly: boolean;
};

export type HelpDocsLoadResult = {
  sourcePath: string;
  pages: HelpDocsPageSeed[];
};

@Injectable()
export class HelpContentDocsLoader {
  private readonly logger = new Logger(HelpContentDocsLoader.name);

  async loadPages(): Promise<HelpDocsLoadResult> {
    const docsDir = await this.resolveDocsDirectory();
    const navigationPath = join(docsDir, 'navigation.json');
    const contentDir = join(docsDir, 'content');
    const navigation = await this.readNavigation(navigationPath);
    const pages: HelpDocsPageSeed[] = [];
    await this.appendNodes(navigation, pages, contentDir, null);

    if (pages.length == 0) {
      throw new InternalServerErrorException(
        'Chưa có nội dung hướng dẫn để khởi tạo runtime.',
      );
    }

    this.logger.log(
      `Help docs loaded: sourcePath=${docsDir} pageCount=${pages.length}`,
    );
    return { sourcePath: docsDir, pages };
  }

  private async appendNodes(
    rawNodes: unknown,
    pages: HelpDocsPageSeed[],
    contentDir: string,
    parentKey: string | null,
  ) {
    if (!Array.isArray(rawNodes)) {
      throw new InternalServerErrorException(
        'Cấu trúc navigation hướng dẫn không hợp lệ.',
      );
    }

    for (let index = 0; index < rawNodes.length; index += 1) {
      const node = rawNodes[index] as DocsNavigationNode;
      const key = this.requiredText(node.key, 'key');
      const title = this.requiredText(node.title, 'title');
      const fileName = this.safeFileName(node.file);
      const markdownPath = join(contentDir, fileName);
      const markdown = await this.readMarkdown(markdownPath, key);

      pages.push({
        key,
        title,
        fileName,
        parentKey,
        sortOrder: index,
        markdown,
        isPublished: true,
        isAuthenticatedOnly: false,
      });

      if (node.children != null) {
        await this.appendNodes(node.children, pages, contentDir, key);
      }
    }
  }

  private async readNavigation(path: string) {
    try {
      const raw = await readFile(path, 'utf8');
      return JSON.parse(raw);
    } catch (error) {
      this.logger.error(`Help docs navigation read failed: path=${path}`);
      throw new InternalServerErrorException(
        'Không đọc được cấu trúc hướng dẫn hiện tại.',
      );
    }
  }

  private async readMarkdown(path: string, key: string) {
    try {
      return await readFile(path, 'utf8');
    } catch (error) {
      this.logger.error(
        `Help docs markdown read failed: key=${key} path=${path}`,
      );
      throw new InternalServerErrorException(
        `Không đọc được nội dung hướng dẫn cho trang ${key}.`,
      );
    }
  }

  private async resolveDocsDirectory() {
    const candidates = [
      resolve(process.cwd(), 'docs', 'help'),
      resolve(process.cwd(), '..', 'docs', 'help'),
      resolve(__dirname, '..', '..', '..', 'docs', 'help'),
      resolve(__dirname, '..', '..', '..', '..', 'docs', 'help'),
    ];

    for (const candidate of candidates) {
      if (await this.pathExists(join(candidate, 'navigation.json'))) {
        return candidate;
      }
    }

    this.logger.error(
      `Help docs directory not found: candidates=${candidates.join(',')}`,
    );
    throw new InternalServerErrorException(
      'Không tìm thấy nguồn docs/help để khởi tạo hướng dẫn.',
    );
  }

  private requiredText(value: unknown, field: string) {
    const text = String(value ?? '').trim();
    if (!text) {
      throw new InternalServerErrorException(
        `Thiếu ${field} trong navigation hướng dẫn.`,
      );
    }
    return text;
  }

  private safeFileName(value: unknown) {
    const text = String(value ?? '').trim();
    const fileName = basename(text);
    if (!text || fileName != text) {
      throw new InternalServerErrorException(
        'Tệp nội dung hướng dẫn không hợp lệ.',
      );
    }
    return fileName;
  }

  private async pathExists(target: string) {
    try {
      await access(target);
      return true;
    } catch (error) {
      return false;
    }
  }
}
