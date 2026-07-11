import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { PrismaService } from '../prisma/prisma.service';

export type SalesReportCategoryGroupDto = {
  id: string;
  catGroupName: string;
  catGroupNameVi: string;
  defaultType: string | null;
  sourceRowCount: number;
  sortOrder: number;
};

export type SalesReportDeepestCategoryMatchDto = {
  categoryType: string;
  categoryGroup: SalesReportCategoryGroupDto;
  sourceLevel: number;
};

const CATEGORY_TRANSLATIONS: Record<string, string> = {
  Laptop: 'Laptop',
  PC: 'Máy tính bộ',
  'Computer components': 'Linh kiện máy tính',
  Apple: 'Apple',
  Peripherals: 'Thiết bị ngoại vi',
  'Office equipment': 'Thiết bị văn phòng',
  'Network and Security equipment': 'Thiết bị mạng và an ninh',
  Software: 'Phần mềm',
  'Entertainment and Digital devices': 'Thiết bị giải trí và kỹ thuật số',
  Accessories: 'Phụ kiện',
  Electric: 'Điện máy',
  'Small Domestic Appliances': 'Điện gia dụng',
  'Spare parts': 'Linh kiện thay thế',
  'Value added service': 'Dịch vụ gia tăng',
  Service: 'Dịch vụ',
  Others: 'Khác',
};

@Injectable()
export class SalesReportCategoriesService {
  private readonly logger = new Logger(SalesReportCategoriesService.name);
  private readonly syncTtlMs = 60_000;
  private lastSyncedAt = 0;
  private cachedCategories: SalesReportCategoryGroupDto[] = [];
  private cachedDeepestCategoryByKey = new Map<
    string,
    { categoryType: string; categoryGroupId: string }
  >();

  constructor(private readonly prisma: PrismaService) {}

  async listCategories() {
    await this.ensureSynced();
    return this.cachedCategories;
  }

  async requireCategory(id: string) {
    const normalizedId = this.normalizeCategoryId(id);
    await this.ensureSynced();
    const category = this.cachedCategories.find(
      (item) => item.id === normalizedId,
    );
    if (!category) {
      throw new BadRequestException('Vui lòng chọn ngành hàng hợp lệ.');
    }
    return category;
  }

  async requireCategories(ids: string[]) {
    const normalizedIds = Array.from(
      new Set(ids.map((id) => this.normalizeCategoryId(id)).filter(Boolean)),
    );
    await this.ensureSynced();
    const categories = normalizedIds
      .map((id) => this.cachedCategories.find((item) => item.id === id))
      .filter((category): category is SalesReportCategoryGroupDto =>
        Boolean(category),
      );
    if (
      normalizedIds.length === 0 ||
      categories.length !== normalizedIds.length
    ) {
      throw new BadRequestException('Vui lòng chọn ngành hàng hợp lệ.');
    }
    return categories;
  }

  async matchTypeFromListingCategories(categories: unknown) {
    const match = await this.matchDeepestListingCategory(categories);
    return match?.categoryType ?? null;
  }

  async matchDeepestListingCategory(
    categories: unknown,
  ): Promise<SalesReportDeepestCategoryMatchDto | null> {
    await this.ensureSynced();
    const candidates = this.listingCategoryCandidates(categories);
    if (candidates.length === 0) return null;
    const deepestLevel = Math.max(
      ...candidates.map((candidate) => candidate.rank),
    );
    const deepestCandidates = candidates.filter(
      (candidate) => candidate.rank === deepestLevel,
    );
    for (const candidate of deepestCandidates) {
      const match = this.cachedDeepestCategoryByKey.get(
        this.normalizeTypeLookupKey(candidate.value),
      );
      if (!match) continue;
      const categoryGroup = this.cachedCategories.find(
        (category) => category.id === match.categoryGroupId,
      );
      if (!categoryGroup) continue;
      this.logger.log(
        `Sales report deepest Listing category matched: sourceLevel=${deepestLevel} categoryType=${match.categoryType} categoryGroup=${categoryGroup.id}`,
      );
      return {
        categoryType: match.categoryType,
        categoryGroup,
        sourceLevel: deepestLevel,
      };
    }
    this.logger.warn(
      `Sales report deepest Listing category not matched: sourceLevel=${deepestLevel} candidateCount=${deepestCandidates.length}`,
    );
    return null;
  }

  private async ensureSynced() {
    const now = Date.now();
    if (
      this.cachedCategories.length > 0 &&
      now - this.lastSyncedAt < this.syncTtlMs
    ) {
      return;
    }
    const rows = await this.readCategoryRows();
    const groups = this.groupRows(rows);
    await this.prisma.$transaction(
      groups.map((group) =>
        this.prisma.salesReportCategoryGroup.upsert({
          where: { id: group.id },
          update: {
            catGroupName: group.catGroupName,
            catGroupNameVi: group.catGroupNameVi,
            sourceRowCount: group.sourceRowCount,
            sortOrder: group.sortOrder,
            isActive: true,
          },
          create: {
            id: group.id,
            catGroupName: group.catGroupName,
            catGroupNameVi: group.catGroupNameVi,
            sourceRowCount: group.sourceRowCount,
            sortOrder: group.sortOrder,
            isActive: true,
          },
        }),
      ),
    );
    this.cachedCategories = groups;
    this.cachedDeepestCategoryByKey = this.buildDeepestCategoryMap(rows);
    this.lastSyncedAt = now;
    this.logger.log(`Sales report categories synced: count=${groups.length}`);
  }

  private async readCategoryRows() {
    const filePath = this.categoryCsvPath();
    try {
      const content = await fs.readFile(filePath, 'utf8');
      const rows = this.parseCsv(content);
      if (rows.length === 0) return [];
      const headers = rows[0].map((header) => header.trim());
      return rows
        .slice(1)
        .filter((row) => row.some((cell) => cell.trim() !== ''))
        .map((row) =>
          Object.fromEntries(
            headers.map((header, index) => [header, row[index]?.trim() ?? '']),
          ),
        );
    } catch (error) {
      this.logger.error(
        `Sales report category CSV read failed: path=${filePath} error=${String(error)}`,
      );
      throw new ServiceUnavailableException(
        'Chưa tải được danh sách ngành hàng. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  private groupRows(rows: Array<Record<string, string>>) {
    const byId = new Map<
      string,
      {
        id: string;
        catGroupName: string;
        sourceRowCount: number;
        typeCounts: Map<string, number>;
      }
    >();
    for (const row of rows) {
      const id = this.normalizeCategoryId(row['Cat group ID']);
      const catGroupName = String(row['Cat group name'] || '').trim();
      if (!id || !catGroupName) continue;
      const type = this.normalizeCategoryType(row.Type);
      const current = byId.get(id);
      if (current) {
        current.sourceRowCount += 1;
        if (type) {
          current.typeCounts.set(type, (current.typeCounts.get(type) ?? 0) + 1);
        }
        continue;
      }
      byId.set(id, {
        id,
        catGroupName,
        sourceRowCount: 1,
        typeCounts: type ? new Map([[type, 1]]) : new Map(),
      });
    }
    return Array.from(byId.values()).map((group, index) => ({
      id: group.id,
      catGroupName: group.catGroupName,
      catGroupNameVi:
        CATEGORY_TRANSLATIONS[group.catGroupName] || group.catGroupName,
      defaultType: this.primaryType(group.typeCounts),
      sourceRowCount: group.sourceRowCount,
      sortOrder: index + 1,
    }));
  }

  private buildDeepestCategoryMap(rows: Array<Record<string, string>>) {
    const candidatesByKey = new Map<
      string,
      Map<string, { categoryType: string; categoryGroupId: string }>
    >();
    for (const row of rows) {
      const categoryType = this.normalizeCategoryType(row.Type);
      const categoryGroupId = this.normalizeCategoryId(row['Cat group ID']);
      if (!categoryType || !categoryGroupId) continue;
      const lookupKeys = [
        'Subcat ID lowest level',
        'Subcat name lowest level',
        'Subcat 2 ID',
        'Subcat 2 name',
      ];
      for (const key of lookupKeys) {
        const lookupKey = this.normalizeTypeLookupKey(row[key]);
        if (!lookupKey) continue;
        const matches = candidatesByKey.get(lookupKey) ?? new Map();
        matches.set(`${categoryGroupId}:${categoryType}`, {
          categoryType,
          categoryGroupId,
        });
        candidatesByKey.set(lookupKey, matches);
      }
    }
    return new Map(
      Array.from(candidatesByKey.entries()).flatMap(([key, matches]) =>
        matches.size === 1 ? [[key, Array.from(matches.values())[0]]] : [],
      ),
    );
  }

  private listingCategoryCandidates(categories: unknown) {
    const source = Array.isArray(categories)
      ? categories
      : categories && typeof categories === 'object'
        ? Object.values(categories as Record<string, unknown>)
        : [];
    return source.flatMap((item) => {
      if (!item || typeof item !== 'object') return [];
      const record = item as Record<string, unknown>;
      const rank = this.firstNumber(
        record.level,
        record.lvl,
        record.categoryLevel,
        record.depth,
        record.displayLevel,
      );
      if (rank === null) return [];
      return [
        record.code,
        record.id,
        record.categoryCode,
        record.categoryId,
        record.name,
        record.displayName,
        record.categoryName,
      ]
        .map((value) => this.rawText(value))
        .filter((value): value is string => Boolean(value))
        .map((value) => ({ value, rank }));
    });
  }

  private parseCsv(content: string) {
    const rows: string[][] = [];
    let row: string[] = [];
    let cell = '';
    let inQuotes = false;

    for (let index = 0; index < content.length; index += 1) {
      const char = content[index];
      const nextChar = content[index + 1];
      if (char === '"') {
        if (inQuotes && nextChar === '"') {
          cell += '"';
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }
      if (char === ',' && !inQuotes) {
        row.push(cell);
        cell = '';
        continue;
      }
      if ((char === '\n' || char === '\r') && !inQuotes) {
        if (char === '\r' && nextChar === '\n') index += 1;
        row.push(cell);
        rows.push(row);
        row = [];
        cell = '';
        continue;
      }
      cell += char;
    }
    if (cell !== '' || row.length > 0) {
      row.push(cell);
      rows.push(row);
    }
    return rows;
  }

  private categoryCsvPath() {
    const override = process.env.SALES_REPORT_CATEGORIES_CSV?.trim();
    if (override) return path.resolve(process.cwd(), override);
    const cwd = process.cwd();
    if (path.basename(cwd).toLowerCase() === 'backend-nest') {
      return path.resolve(cwd, '..', 'data', 'categories.csv');
    }
    return path.resolve(cwd, 'data', 'categories.csv');
  }

  private normalizeCategoryId(value: unknown) {
    return String(value || '')
      .trim()
      .toUpperCase()
      .replace(/[^A-Z0-9_]/g, '');
  }

  private normalizeCategoryType(value: unknown) {
    const text = String(value || '')
      .trim()
      .replace(/\s+/g, '');
    return text ? text.slice(0, 80) : null;
  }

  private normalizeTypeLookupKey(value: unknown) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '');
  }

  private rawText(value: unknown) {
    const text = String(value ?? '').trim();
    return text || null;
  }

  private firstNumber(...values: unknown[]) {
    for (const value of values) {
      const number = Number(value);
      if (Number.isFinite(number)) return number;
    }
    return null;
  }

  private primaryType(typeCounts: Map<string, number>) {
    return (
      Array.from(typeCounts.entries()).sort(
        ([leftType, leftCount], [rightType, rightCount]) =>
          rightCount - leftCount || leftType.localeCompare(rightType),
      )[0]?.[0] ?? null
    );
  }
}
