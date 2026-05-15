import {
  IsEnum,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
} from 'class-validator';
import { WarrantyStatus } from '@prisma/client';

export class CreateWarrantyDto {
  @IsString()
  @MaxLength(128)
  @Matches(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/)
  receipt!: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  customerName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  customerPhone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(240)
  productName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  serialNumber?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  issue?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10000)
  imageLinks?: string;
}

export class UpdateWarrantyStatusDto {
  @IsEnum(WarrantyStatus)
  status!: WarrantyStatus;
}
