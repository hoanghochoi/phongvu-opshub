import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Length,
  MaxLength,
} from 'class-validator';

export class BidvTokenDto {
  @IsString()
  @IsIn(['client_credentials'])
  grant_type!: 'client_credentials';
}

export class BidvBalanceChangesDto {
  @IsString()
  @IsIn(['BIDV'])
  bankCode!: 'BIDV';

  @IsString()
  data!: string;
}

export class CreateBankApiClientDto {
  @IsString()
  @Length(3, 100)
  displayName!: string;
}

export class GenerateBankPgpKeyDto {
  @IsString()
  @Length(3, 100)
  displayName!: string;
}

export class ImportBankPgpKeyDto {
  @IsString()
  @Length(3, 100)
  displayName!: string;

  @IsString()
  @MaxLength(100_000)
  publicKeyArmor!: string;

  @IsString()
  @MaxLength(200_000)
  privateKeyArmor!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  passphrase?: string;
}

export class RevokeBankConnectionDto {
  @IsOptional()
  @IsBoolean()
  recoveryOverride?: boolean;
}

export class UpdateBankConnectionControlDto {
  @IsBoolean()
  ingressEnabled!: boolean;

  @IsBoolean()
  projectionEnabled!: boolean;
}
