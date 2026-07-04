import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { HelpContentPage } from '@prisma/client';
import { isSuperAdminRole } from '../common/system-role';
import { PrismaService } from '../prisma/prisma.service';
import {
  CreateHelpContentPageDto,
  SeedHelpContentDto,
  UpdateHelpContentPageDto,
} from './help-content.dto';
import {
  HelpContentDocsLoader,
  HelpDocsPageSeed,
} from './help-content.docs-loader';

type HelpSnapshotOptions = {
  includeEditorFields: boolean;
};

@Injectable()
export class HelpContentService {
  private readonly logger = new Logger(HelpContentService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly docsLoader: HelpContentDocsLoader,
  ) {}

  async getPublicContent() {
    this.logger.log('Help content public load started');
    try {
      await this.ensureSeeded();
      const pages = await this.listPages({ publishedOnly: true });
      const snapshot = this.buildSnapshot(pages, {
        includeEditorFields: false,
      });
      this.logger.log(
        `Help content public load succeeded: pageCount=${pages.length}`,
      );
      return snapshot;
    } catch (error) {
      this.logger.error(
        `Help content public load failed: message=${this.errorMessage(error)}`,
      );
      throw error;
    }
  }

  async getAdminPages(user: any) {
    this.assertSuperAdmin(user);
    this.logger.log(
      `Help content admin load started: user=${this.safeUserLabel(user)}`,
    );
    try {
      await this.ensureSeeded();
      const pages = await this.listPages();
      const snapshot = this.buildSnapshot(pages, { includeEditorFields: true });
      this.logger.log(
        `Help content admin load succeeded: user=${this.safeUserLabel(user)} pageCount=${pages.length}`,
      );
      return snapshot;
    } catch (error) {
      this.logger.error(
        `Help content admin load failed: user=${this.safeUserLabel(user)} message=${this.errorMessage(error)}`,
      );
      throw error;
    }
  }

  async createPage(user: any, dto: CreateHelpContentPageDto) {
    this.assertSuperAdmin(user);
    try {
      await this.ensureSeeded();
      const payload = await this.buildCreatePayload(dto);
      this.logger.log(
        `Help content save started: mode=create user=${this.safeUserLabel(user)} key=${payload.key} parentKey=${payload.parentKey || 'root'} markdownLength=${payload.markdown.length}`,
      );
      const created = await this.prisma.helpContentPage.create({
        data: {
          ...payload,
          updatedByUserId: this.optionalText(user?.id, 80),
          updatedByEmail: this.normalizeEmail(user?.email),
          seededFromDocsAt: null,
        },
      });
      this.logger.log(
        `Help content save succeeded: mode=create user=${this.safeUserLabel(user)} key=${created.key}`,
      );
      return this.serializePage(created, true);
    } catch (error) {
      this.logger.error(
        `Help content save failed: mode=create user=${this.safeUserLabel(user)} message=${this.errorMessage(error)}`,
      );
      throw error;
    }
  }

  async updatePage(user: any, key: string, dto: UpdateHelpContentPageDto) {
    this.assertSuperAdmin(user);
    try {
      const existing = await this.prisma.helpContentPage.findUnique({
        where: { key: this.normalizeKey(key) },
      });
      if (!existing) {
        throw new NotFoundException(
          'Không tìm thấy trang hướng dẫn cần cập nhật.',
        );
      }

      const payload = await this.buildUpdatePayload(existing, dto);
      this.logger.log(
        `Help content save started: mode=update user=${this.safeUserLabel(user)} key=${existing.key} parentKey=${payload.parentKey || 'root'} markdownLength=${payload.markdown.length}`,
      );
      const updated = await this.prisma.helpContentPage.update({
        where: { key: existing.key },
        data: {
          ...payload,
          updatedByUserId: this.optionalText(user?.id, 80),
          updatedByEmail: this.normalizeEmail(user?.email),
        },
      });
      this.logger.log(
        `Help content save succeeded: mode=update user=${this.safeUserLabel(user)} key=${updated.key}`,
      );
      return this.serializePage(updated, true);
    } catch (error) {
      this.logger.error(
        `Help content save failed: mode=update user=${this.safeUserLabel(user)} key=${this.normalizeKey(key)} message=${this.errorMessage(error)}`,
      );
      throw error;
    }
  }

  async seedFromDocs(user: any, dto: SeedHelpContentDto) {
    this.assertSuperAdmin(user);
    const overwriteExisting = dto.overwriteExisting == true;
    const startedAt = Date.now();
    this.logger.log(
      `Help content docs restore started: user=${this.safeUserLabel(user)} overwriteExisting=${overwriteExisting}`,
    );

    try {
      const result = await this.applyDocsSeed(
        overwriteExisting ? 'replace' : 'seed-if-empty',
        user,
      );
      this.logger.log(
        `Help content docs restore succeeded: user=${this.safeUserLabel(user)} overwriteExisting=${overwriteExisting} seeded=${result.seeded} pageCount=${result.pageCount} durationMs=${Date.now() - startedAt}`,
      );
      return {
        seeded: result.seeded,
        overwriteExisting,
        pageCount: result.pageCount,
        sourcePath: result.sourcePath,
        seededAt: result.seededAt,
      };
    } catch (error) {
      this.logger.error(
        `Help content docs restore failed: user=${this.safeUserLabel(user)} overwriteExisting=${overwriteExisting}`,
      );
      throw error;
    }
  }

  private async ensureSeeded() {
    await this.applyDocsSeed('seed-if-empty', null);
  }

  private async applyDocsSeed(
    mode: 'seed-if-empty' | 'replace',
    user: any,
  ): Promise<{
    seeded: boolean;
    pageCount: number;
    sourcePath: string;
    seededAt: Date;
  }> {
    const existingCount = await this.prisma.helpContentPage.count();
    if (mode == 'seed-if-empty' && existingCount > 0) {
      return {
        seeded: false,
        pageCount: existingCount,
        sourcePath: '',
        seededAt: new Date(),
      };
    }

    const docs = await this.docsLoader.loadPages();
    const seededAt = new Date();
    const records = docs.pages.map((page) =>
      this.seedRecord(page, seededAt, user),
    );

    if (mode == 'replace') {
      await this.prisma.$transaction([
        this.prisma.helpContentPage.deleteMany({}),
        this.prisma.helpContentPage.createMany({ data: records }),
      ]);
      return {
        seeded: true,
        pageCount: records.length,
        sourcePath: docs.sourcePath,
        seededAt,
      };
    }

    await this.prisma.helpContentPage.createMany({ data: records });
    return {
      seeded: true,
      pageCount: records.length,
      sourcePath: docs.sourcePath,
      seededAt,
    };
  }

  private seedRecord(page: HelpDocsPageSeed, seededAt: Date, user: any) {
    return {
      key: page.key,
      title: page.title,
      fileName: page.fileName,
      parentKey: page.parentKey,
      sortOrder: page.sortOrder,
      markdown: page.markdown,
      isPublished: page.isPublished,
      updatedByUserId: this.optionalText(user?.id, 80),
      updatedByEmail: this.normalizeEmail(user?.email),
      seededFromDocsAt: seededAt,
    };
  }

  private async listPages(options?: { publishedOnly?: boolean }) {
    return this.prisma.helpContentPage.findMany({
      where: options?.publishedOnly ? { isPublished: true } : undefined,
      orderBy: [{ parentKey: 'asc' }, { sortOrder: 'asc' }, { key: 'asc' }],
    });
  }

  private async buildCreatePayload(dto: CreateHelpContentPageDto) {
    const key = this.normalizeKey(dto.key);
    const existing = await this.prisma.helpContentPage.findUnique({
      where: { key },
      select: { key: true },
    });
    if (existing) {
      throw new BadRequestException('Khóa trang hướng dẫn đã tồn tại.');
    }

    const parentKey = await this.validateParentKey(dto.parentKey, null);
    return {
      key,
      title: this.requiredTitle(dto.title),
      fileName: this.normalizeFileName(dto.fileName, key),
      parentKey,
      sortOrder: this.normalizeSortOrder(dto.sortOrder),
      markdown: this.normalizeMarkdown(dto.markdown),
      isPublished: dto.isPublished != false,
    };
  }

  private async buildUpdatePayload(
    existing: HelpContentPage,
    dto: UpdateHelpContentPageDto,
  ) {
    const hasParentKey = Object.prototype.hasOwnProperty.call(dto, 'parentKey');
    return {
      title: dto.title == null ? existing.title : this.requiredTitle(dto.title),
      fileName:
        dto.fileName == null
          ? existing.fileName
          : this.normalizeFileName(dto.fileName, existing.key),
      parentKey: hasParentKey
        ? await this.validateParentKey(dto.parentKey, existing.key)
        : existing.parentKey,
      sortOrder:
        dto.sortOrder == null
          ? existing.sortOrder
          : this.normalizeSortOrder(dto.sortOrder),
      markdown:
        dto.markdown == null
          ? existing.markdown
          : this.normalizeMarkdown(dto.markdown),
      isPublished: dto.isPublished ?? existing.isPublished,
    };
  }

  private buildSnapshot(
    pages: HelpContentPage[],
    options: HelpSnapshotOptions,
  ) {
    const serializedPages = pages.map((page) =>
      this.serializePage(page, options.includeEditorFields),
    );
    const updatedAt = pages.reduce<Date | null>((latest, page) => {
      if (latest == null || page.updatedAt.getTime() > latest.getTime()) {
        return page.updatedAt;
      }
      return latest;
    }, null);
    return {
      source: 'runtime',
      updatedAt,
      navigation: this.buildNavigation(pages),
      pages: serializedPages,
    };
  }

  private buildNavigation(pages: HelpContentPage[]) {
    const nodes = new Map<
      string,
      {
        key: string;
        title: string;
        fileName: string;
        parentKey: string | null;
        sortOrder: number;
        isPublished: boolean;
        updatedAt: Date;
        children: any[];
      }
    >();

    for (const page of pages) {
      nodes.set(page.key, {
        key: page.key,
        title: page.title,
        fileName: page.fileName,
        parentKey: page.parentKey,
        sortOrder: page.sortOrder,
        isPublished: page.isPublished,
        updatedAt: page.updatedAt,
        children: [],
      });
    }

    const roots: any[] = [];
    for (const page of pages) {
      const node = nodes.get(page.key);
      if (!node) continue;
      if (page.parentKey != null && nodes.has(page.parentKey)) {
        nodes.get(page.parentKey)?.children.push(node);
        continue;
      }
      roots.push(node);
    }

    finalSort(roots);
    return roots;
  }

  private serializePage(page: HelpContentPage, includeEditorFields: boolean) {
    return {
      id: page.id,
      key: page.key,
      title: page.title,
      fileName: page.fileName,
      parentKey: page.parentKey,
      sortOrder: page.sortOrder,
      markdown: page.markdown,
      isPublished: page.isPublished,
      seededFromDocsAt: page.seededFromDocsAt,
      updatedAt: page.updatedAt,
      ...(includeEditorFields
        ? {
            updatedByUserId: page.updatedByUserId,
            updatedByEmail: page.updatedByEmail,
          }
        : {}),
    };
  }

  private assertSuperAdmin(user: any) {
    if (isSuperAdminRole(user?.role)) return;
    this.logger.warn(
      `Help content admin blocked: user=${this.safeUserLabel(user)} role=${String(user?.role || 'unknown')}`,
    );
    throw new ForbiddenException('Chỉ Super Admin mới được quản lý hướng dẫn.');
  }

  private async validateParentKey(
    parentKey: string | null | undefined,
    key: string | null,
  ) {
    if (parentKey == null) return null;
    const normalized = this.normalizeKey(parentKey);
    if (key != null && normalized == key) {
      throw new BadRequestException(
        'Trang hướng dẫn không thể tự làm trang cha.',
      );
    }
    const parent = await this.prisma.helpContentPage.findUnique({
      where: { key: normalized },
      select: { key: true },
    });
    if (!parent) {
      throw new BadRequestException('Trang cha của hướng dẫn không tồn tại.');
    }
    return normalized;
  }

  private requiredTitle(value: unknown) {
    const text = String(value ?? '').trim();
    if (!text) {
      throw new BadRequestException('Tiêu đề trang hướng dẫn là bắt buộc.');
    }
    return text.slice(0, 160);
  }

  private normalizeKey(value: unknown) {
    const text = String(value ?? '')
      .trim()
      .toLowerCase();
    if (!text) {
      throw new BadRequestException('Khóa trang hướng dẫn là bắt buộc.');
    }
    if (!/^[a-z0-9-]+$/.test(text)) {
      throw new BadRequestException(
        'Khóa trang chỉ gồm chữ thường, số và dấu gạch ngang.',
      );
    }
    return text;
  }

  private normalizeFileName(value: unknown, fallbackKey: string) {
    const text = String(value ?? '').trim();
    const base = text || `${fallbackKey}.md`;
    const clean = base.replace(/[^a-zA-Z0-9._-]/g, '-');
    if (!clean.toLowerCase().endsWith('.md')) {
      return `${clean}.md`;
    }
    return clean;
  }

  private normalizeSortOrder(value: number | undefined) {
    const sortOrder = Number(value ?? 0);
    if (!Number.isFinite(sortOrder) || sortOrder < 0) {
      throw new BadRequestException('Thứ tự hiển thị phải từ 0 trở lên.');
    }
    return Math.floor(sortOrder);
  }

  private normalizeMarkdown(value: unknown) {
    return String(value ?? '');
  }

  private normalizeEmail(value: unknown) {
    const text = String(value ?? '')
      .trim()
      .toLowerCase();
    return text || null;
  }

  private optionalText(value: unknown, maxLength: number) {
    const text = String(value ?? '').trim();
    return text ? text.slice(0, maxLength) : null;
  }

  private safeUserLabel(user: any) {
    return (
      this.normalizeEmail(user?.email) ||
      this.optionalText(user?.id, 80) ||
      'missing'
    );
  }

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}

function finalSort(nodes: any[]) {
  nodes.sort((left, right) => {
    const sortDelta =
      Number(left.sortOrder || 0) - Number(right.sortOrder || 0);
    if (sortDelta != 0) return sortDelta;
    return String(left.key || '').localeCompare(String(right.key || ''));
  });
  for (const node of nodes) {
    finalSort(Array.isArray(node.children) ? node.children : []);
  }
}
