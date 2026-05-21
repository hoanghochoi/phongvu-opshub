import { IsIn, IsObject, IsOptional, IsString, MaxLength } from 'class-validator';

export class PaymentNotificationAckDto {
  @IsString()
  @MaxLength(120)
  clientId!: string;

  @IsIn(['DELIVERED', 'PLAYED', 'FAILED'])
  event!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  error?: string;
}

export class CreateAppLogDto {
  @IsIn(['debug', 'info', 'warn', 'error', 'fatal'])
  level!: string;

  @IsString()
  @MaxLength(80)
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
