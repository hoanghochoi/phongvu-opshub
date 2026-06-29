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
  sourceRowCount: number;
  sortOrder: number;
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
  private cachedCategoryAliases = new Map<string, string[]>();

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
      .filter(
        (category): category is SalesReportCategoryGroupDto =>
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

  async matchCategoryFromErp(values: Array<string | null | undefined>) {
    const categories = await this.matchCategoriesFromErp(values);
    return categories[0] ?? null;
  }

  async matchCategoriesFromErp(values: Array<string | null | undefined>) {
    await this.ensureSynced();
    const normalizedValues = this.normalizeErpValues(values);
    this.logger.log(
      `Sales report category match started: valueCount=${normalizedValues.length} categoryCount=${this.cachedCategories.length}`,
    );
    const matched: SalesReportCategoryGroupDto[] = [];
    for (const category of this.cachedCategories) {
      const candidates = [
        this.normalizeComparable(category.id),
        this.normalizeComparable(category.catGroupName),
        this.normalizeComparable(category.catGroupNameVi),
        ...(this.cachedCategoryAliases.get(category.id) || []),
      ];
      if (
        candidates.some((candidate) =>
          this.matchesCandidate(candidate, normalizedValues),
        )
      ) {
        matched.push(category);
      }
    }
    if (matched.length > 0) {
      this.logger.log(
        `Sales report category matched from ERP: categories=${matched
          .map((category) => category.id)
          .join(',')}`,
      );
      return matched;
    }
    this.logger.warn(
      `Sales report category not matched from ERP: valueCount=${normalizedValues.length}`,
    );
    return [];
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
    this.cachedCategoryAliases = this.buildCategoryAliases(rows);
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
      { id: string; catGroupName: string; sourceRowCount: number }
    >();
    for (const row of rows) {
      const id = this.normalizeCategoryId(row['Cat group ID']);
      const catGroupName = String(row['Cat group name'] || '').trim();
      if (!id || !catGroupName) continue;
      const current = byId.get(id);
      if (current) {
        current.sourceRowCount += 1;
        continue;
      }
      byId.set(id, { id, catGroupName, sourceRowCount: 1 });
    }
    return Array.from(byId.values()).map((group, index) => ({
      ...group,
      catGroupNameVi:
        CATEGORY_TRANSLATIONS[group.catGroupName] || group.catGroupName,
      sortOrder: index + 1,
    }));
  }

  private buildCategoryAliases(rows: Array<Record<string, string>>) {
    const aliases = new Map<string, Set<string>>();
    for (const row of rows) {
      const id = this.normalizeCategoryId(row['Cat group ID']);
      if (!id) continue;
      const current = aliases.get(id) ?? new Set<string>();
      for (const key of ['Subcat 2 name', 'Subcat name lowest level']) {
        const value = this.normalizeComparable(row[key]);
        if (value) current.add(value);
      }
      aliases.set(id, current);
    }
    return new Map(
      Array.from(aliases.entries()).map(([id, values]) => [
        id,
        Array.from(values.values()),
      ]),
    );
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

  private normalizeComparable(value: unknown) {
    return String(value || '')
      .trim()
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }

  private normalizeErpValues(values: Array<string | null | undefined>) {
    const normalized = new Set<string>();
    for (const value of values) {
      const raw = String(value || '').trim();
      if (!raw) continue;
      const full = this.normalizeComparable(raw);
      if (full) normalized.add(full);
      for (const fragment of raw.split(/[/>|]+/g)) {
        const text = this.normalizeComparable(fragment);
        if (text) normalized.add(text);
      }
    }
    return Array.from(normalized.values());
  }

  private matchesCandidate(candidate: string, values: string[]) {
    if (!candidate) return false;
    return values.some(
      (value) =>
        value === candidate ||
        value.includes(candidate) ||
        (this.canUseReverseMatch(value) && candidate.includes(value)),
    );
  }

  private canUseReverseMatch(value: string) {
    return value.length >= 10 && value.split(/\s+/g).length >= 3;
  }
}
