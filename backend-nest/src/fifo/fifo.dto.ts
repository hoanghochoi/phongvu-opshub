import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class FifoCheckDto {
  @IsString()
  text!: string;

  @IsOptional()
  @IsBoolean()
  includeExported?: boolean;
}

export class FifoExportDto {
  @IsString()
  inventoryId!: string;

  @IsBoolean()
  exported!: boolean;
}
