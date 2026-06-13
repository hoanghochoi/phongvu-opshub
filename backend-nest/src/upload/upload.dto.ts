import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';

export class UploadWarrantyImagesDto {
  @IsString()
  @MaxLength(128)
  @Matches(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/)
  receipt!: string;

  @IsOptional()
  @IsString()
  @MaxLength(320)
  user?: string;
}
