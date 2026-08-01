import { Transform } from 'class-transformer';
import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
} from 'class-validator';

const DECIMAL_SEQUENCE = /^(0|[1-9][0-9]{0,18})$/;
const CLIENT_MESSAGE_ID = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$/;

export class SupportMessagePageQueryDto {
  @IsOptional()
  @Matches(DECIMAL_SEQUENCE)
  beforeSequence?: string;

  @IsOptional()
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  @Max(50)
  limit = 30;
}

export class SendSupportTextMessageDto {
  @IsString()
  @Matches(CLIENT_MESSAGE_ID)
  clientMessageId: string;

  @IsString()
  text: string;
}

export class SendSupportImageMessageDto {
  @IsString()
  @Matches(CLIENT_MESSAGE_ID)
  clientMessageId: string;
}

export class ResolveSupportConversationDto {
  @IsString()
  @Matches(DECIMAL_SEQUENCE)
  expectedLastMessageSequence: string;
}

export class MarkSupportConversationReadDto {
  @IsString()
  @Matches(DECIMAL_SEQUENCE)
  lastReadSequence: string;
}

export class ListSupportConversationsQueryDto {
  @IsIn(['UNASSIGNED', 'MINE', 'ACTIVE', 'RESOLVED'])
  bucket: 'UNASSIGNED' | 'MINE' | 'ACTIVE' | 'RESOLVED';

  @IsOptional()
  @IsString()
  @MaxLength(120)
  query?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  cursor?: string;

  @IsOptional()
  @Transform(({ value }) => Number(value))
  @IsInt()
  @Min(1)
  @Max(50)
  limit = 30;
}
