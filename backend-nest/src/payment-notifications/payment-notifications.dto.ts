import {
  IsIn,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

export class ListPaymentNotificationsQueryDto {
  @IsString()
  @MaxLength(120)
  clientId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeCode?: string;

  @IsOptional()
  @IsString()
  @MaxLength(4)
  limit?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  afterCreatedAt?: string;
}

export class PaymentNotificationDeliveryMetricsQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(3)
  windowHours?: string;
}

export class PaymentNotificationDeliveryHistoryQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(2)
  limit?: string;
}

export class PaymentNotificationAckDto {
  @IsString()
  @MaxLength(120)
  clientId!: string;

  @IsIn([
    'DELIVERED',
    'STREAM_STARTED',
    'PLAYED',
    'FAILED',
    'SILENCED',
    'PLAYBACK_FAILED',
  ])
  event!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  error?: string;
}

export class PaymentNotificationClaimDto {
  @IsString()
  @MinLength(1)
  @MaxLength(120)
  clientId!: string;
}

export class CreateAppLogDto {
  @IsIn(['debug', 'info', 'warn', 'error', 'fatal'])
  level!: string;

  @IsString()
  @MaxLength(80)
  @Matches(/^[A-Za-z][A-Za-z0-9_.:-]*$/, {
    message: 'Nguồn log không hợp lệ. Vui lòng cập nhật ứng dụng và thử lại.',
  })
  source!: string;

  @IsString()
  @MaxLength(1000)
  message!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  clientId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  storeCode?: string;

  @IsOptional()
  @IsObject()
  context?: Record<string, unknown>;
}
