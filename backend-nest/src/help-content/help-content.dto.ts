import {
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Min,
} from 'class-validator';

const HELP_CONTENT_KEY_PATTERN = /^[a-z0-9-]+$/;

export class CreateHelpContentPageDto {
  @IsString()
  @MaxLength(80)
  @Matches(HELP_CONTENT_KEY_PATTERN, {
    message: 'Khóa trang chỉ gồm chữ thường, số và dấu gạch ngang.',
  })
  key: string;

  @IsString()
  @MaxLength(160)
  title: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  fileName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  @Matches(HELP_CONTENT_KEY_PATTERN, {
    message: 'Khóa trang cha chỉ gồm chữ thường, số và dấu gạch ngang.',
  })
  parentKey?: string | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @IsOptional()
  @IsString()
  @MaxLength(40000)
  markdown?: string;

  @IsOptional()
  @IsBoolean()
  isPublished?: boolean;
}

export class UpdateHelpContentPageDto {
  @IsOptional()
  @IsString()
  @MaxLength(160)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  fileName?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  @Matches(HELP_CONTENT_KEY_PATTERN, {
    message: 'Khóa trang cha chỉ gồm chữ thường, số và dấu gạch ngang.',
  })
  parentKey?: string | null;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;

  @IsOptional()
  @IsString()
  @MaxLength(40000)
  markdown?: string;

  @IsOptional()
  @IsBoolean()
  isPublished?: boolean;
}

export class SeedHelpContentDto {
  @IsOptional()
  @IsBoolean()
  overwriteExisting?: boolean;
}
