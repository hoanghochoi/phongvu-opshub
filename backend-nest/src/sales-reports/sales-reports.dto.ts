import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsBoolean,
  IsIn,
  IsInt,
  IsArray,
  IsOptional,
  IsString,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

export const SALES_REPORT_TYPES = ['PURCHASED', 'NOT_PURCHASED'] as const;

export const SALES_REPORT_EXPORT_TYPES = [
  'HVTC',
  'REVENUE',
  'INSTALLMENT',
] as const;

export const YES_NO_REASON_CODES = [
  'YES',
  'CUSTOMER_BUSY_OR_NO_NEED',
  'OUT_OF_STOCK_OR_NO_EQUIVALENT',
  'PRODUCT_NOT_SOLD_OR_NOT_IN_STORE',
  'PRICE_HIGH',
  'SALES_FORGOT',
  'OTHER',
] as const;

export const EXPERIENCE_REASON_CODES = [
  'YES',
  'CUSTOMER_BUSY_OR_NO_NEED',
  'PRODUCT_NOT_SOLD_OR_NOT_IN_STORE',
  'SALES_FORGOT',
  'OTHER',
] as const;

export const ZALO_REASON_CODES = [
  'YES',
  'CUSTOMER_BUSY_OR_NO_NEED',
  'ALREADY_FOLLOWED_ZALO',
  'NO_SMARTPHONE_OR_NO_ZALO',
  'SALES_FORGOT',
  'OTHER',
] as const;

export const APP_DOWNLOAD_REASON_CODES = [
  'YES',
  'CUSTOMER_BUSY_OR_NO_NEED',
  'ALREADY_INSTALLED_APP',
  'NO_SMARTPHONE_OR_NO_APP',
  'SALES_FORGOT',
  'OTHER',
] as const;

export const NOT_PURCHASED_REASON_CODES = [
  'NOT_SOLD',
  'SERVICE',
  'CUSTOMER_BROWSING',
  'NO_DEMO_STOCK',
  'NO_AVAILABLE_STOCK',
  'PRICE_HESITATION',
  'COMPARE_COMPETITOR',
  'SPEC_NOT_COMPATIBLE',
  'OTHER',
] as const;

export const CUSTOMER_TYPE_CODES = ['BUSINESS', 'PERSONAL'] as const;

export const PROMOTION_CODES = [
  'EXAM_SCORE_EXCHANGE',
  'STUDENT',
  'OTHER',
] as const;

export const INSTALLMENT_STATUSES = ['SUCCESS', 'FAILED'] as const;

export const INSTALLMENT_PARTNER_CODES = [
  'VNPAY_POS',
  'PAYOO_POS',
  'HOMECREDIT_CTTC',
  'SHINHAN_CTTC',
  'HDSAISON_CTTC',
  'AEON_FINANCE_CTTC',
  'MIRAE_ASSET',
  'MPOS',
] as const;

export const INSTALLMENT_NO_INSTALLMENT_REASON_CODES = [
  'NORMAL_INSTALLMENT',
  'BAD_CREDIT_HISTORY',
  'APPRAISAL_OR_INFO_ERROR',
  'HIGH_INTEREST_OR_FEE',
  'MISSING_DOCUMENT_OR_CARD',
  'PRICE_COMPETITOR_COMPARISON',
  'BROWSING_OR_COME_BACK_LATER',
] as const;

export class CheckSalesReportOrderDto {
  @IsString()
  @MaxLength(80)
  orderCode!: string;
}

export class CreateSalesReportDto {
  @IsString()
  @IsIn(SALES_REPORT_TYPES)
  reportType!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  orderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  customerName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  customerPhone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  categoryGroupId?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @MaxLength(40, { each: true })
  categoryGroupIds?: string[];

  @IsOptional()
  @IsString()
  @MaxLength(500)
  customerNeed?: string;

  @IsString()
  @IsIn(YES_NO_REASON_CODES, {
    message: 'Vui lòng chọn kết quả tư vấn 3 giải pháp.',
  })
  consultedSolutionAnswer!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  consultedSolutionOtherReason?: string;

  @IsString()
  @IsIn(EXPERIENCE_REASON_CODES, {
    message: 'Vui lòng chọn kết quả trải nghiệm sản phẩm.',
  })
  experiencedAnswer!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  experiencedOtherReason?: string;

  @IsString()
  @IsIn(ZALO_REASON_CODES, {
    message: 'Vui lòng chọn kết quả quét Zalo.',
  })
  zaloAnswer!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  zaloOtherReason?: string;

  @IsString()
  @IsIn(APP_DOWNLOAD_REASON_CODES, {
    message: 'Vui lòng chọn kết quả tải App PV.',
  })
  appDownloadAnswer!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  appDownloadOtherReason?: string;

  @IsOptional()
  @IsString()
  @IsIn(NOT_PURCHASED_REASON_CODES)
  notPurchasedReason?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notPurchasedOtherReason?: string;

  @IsOptional()
  @IsString()
  @IsIn(CUSTOMER_TYPE_CODES, {
    message: 'Loại khách hàng không hợp lệ.',
  })
  customerType?: string;

  @IsOptional()
  @IsBoolean()
  customerIsStudent?: boolean;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @IsIn(PROMOTION_CODES, {
    each: true,
    message: 'CTKM áp dụng không hợp lệ.',
  })
  promotionCodes?: string[];

  @IsOptional()
  @IsBoolean()
  installmentNeed?: boolean;

  @IsOptional()
  @IsBoolean()
  installmentApproved?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(10_000_000_000)
  installmentLoanAmount?: number;

  @IsOptional()
  @IsString()
  @IsIn(INSTALLMENT_NO_INSTALLMENT_REASON_CODES, {
    message: 'Lý do không trả góp không hợp lệ.',
  })
  installmentNoInstallmentReason?: string;

  @IsOptional()
  @IsString()
  @IsIn(INSTALLMENT_STATUSES, {
    message: 'Trạng thái trả góp không hợp lệ.',
  })
  installmentStatus?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  installmentFailureReason?: string;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @IsIn(INSTALLMENT_PARTNER_CODES, {
    each: true,
    message: 'Đối tác trả góp không hợp lệ.',
  })
  installmentPartnerCodes?: string[];
}

export class ListSalesReportsDto {
  @IsOptional()
  @IsString()
  @IsIn(['ALL', ...SALES_REPORT_TYPES])
  reportType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  orderCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  categoryGroupId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(400)
  storeIds?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  allStores?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  reporter?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  startDate?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  endDate?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export class ExportSalesReportsDto extends ListSalesReportsDto {
  @IsOptional()
  @IsString()
  @IsIn(SALES_REPORT_EXPORT_TYPES)
  exportType?: string;
}

export class ListSalesReportOrdersDto {
  @IsOptional()
  @IsString()
  @MaxLength(10)
  date?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  refresh?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  reportedPage?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  unreportedPage?: number;
}
