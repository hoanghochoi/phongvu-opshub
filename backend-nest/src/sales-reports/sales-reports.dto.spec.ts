import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import {
  ExportSalesReportFollowUpHistoryDto,
  ListSalesReportFollowUpCasesDto,
} from './sales-reports.dto';

describe('Follow-up filter DTOs', () => {
  it.each([
    ListSalesReportFollowUpCasesDto,
    ExportSalesReportFollowUpHistoryDto,
  ])('nhận showroom và một ngành hàng hợp lệ cho %p', (Dto) => {
    const value = plainToInstance(Dto, {
      storeCode: 'CP01',
      categoryGroupId: 'NH01',
    });

    expect(validateSync(value)).toHaveLength(0);
  });

  it.each([
    ListSalesReportFollowUpCasesDto,
    ExportSalesReportFollowUpHistoryDto,
  ])('chặn mã ngành hàng dài quá giới hạn cho %p', (Dto) => {
    const value = plainToInstance(Dto, {
      categoryGroupId: 'N'.repeat(81),
    });

    expect(validateSync(value)).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ property: 'categoryGroupId' }),
      ]),
    );
  });
});
