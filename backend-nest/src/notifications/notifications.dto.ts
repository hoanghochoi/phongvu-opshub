import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsString,
  MaxLength,
} from 'class-validator';

export const APP_NOTIFICATION_SOURCES = [
  'statement_order_transfer',
  'offset_adjustment',
] as const;

export type AppNotificationSource = (typeof APP_NOTIFICATION_SOURCES)[number];

export const APP_NOTIFICATION_SOURCE_STATEMENT_ORDER_TRANSFER =
  'statement_order_transfer';
export const APP_NOTIFICATION_SOURCE_OFFSET_ADJUSTMENT = 'offset_adjustment';

export class MarkAppNotificationsReadDto {
  @IsString()
  @IsIn(APP_NOTIFICATION_SOURCES)
  source!: AppNotificationSource;

  @IsArray()
  @ArrayMaxSize(100)
  @IsString({ each: true })
  @MaxLength(120, { each: true })
  ids!: string[];
}
