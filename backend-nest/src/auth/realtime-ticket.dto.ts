import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';

export class RealtimeTicketRequestDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  @Matches(/^[A-Za-z0-9._-]+$/, {
    message: 'Mã showroom nhận dữ liệu thời gian thực không hợp lệ.',
  })
  storeCode?: string;
}
