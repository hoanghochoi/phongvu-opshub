import {
  Body,
  Controller,
  Get,
  Header,
  Headers,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Request,
  Response,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { Throttle } from '@nestjs/throttler';
import type { Response as ExpressResponse } from 'express';
import { FeatureGuard } from '../feature/feature.guard';
import { RequireFeature } from '../feature/feature.decorator';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { BidvH2hAdminService } from './bidv-h2h-admin.service';
import {
  BidvBalanceChangesDto,
  BidvTokenDto,
  CreateBankApiClientDto,
  GenerateBankPgpKeyDto,
  ImportBankPgpKeyDto,
  RevokeBankConnectionDto,
  UpdateBankConnectionControlDto,
} from './bidv-h2h.dto';
import { BidvH2hIngressService } from './bidv-h2h-ingress.service';
import { BidvH2hOauthService } from './bidv-h2h-oauth.service';

@Controller()
export class BidvH2hController {
  constructor(
    private readonly oauth: BidvH2hOauthService,
    private readonly ingress: BidvH2hIngressService,
  ) {}

  @Post('oauth2/token')
  @HttpCode(HttpStatus.OK)
  @Throttle({ principal: { limit: 600, ttl: 60_000 } })
  async token(
    @Headers('authorization') authorization: unknown,
    @Body() _body: BidvTokenDto,
    @Response({ passthrough: true }) response: ExpressResponse,
  ) {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Pragma', 'no-cache');
    return this.oauth.issueToken(authorization);
  }

  @Post('v1/balance-changes')
  @HttpCode(HttpStatus.OK)
  @Throttle({ principal: { limit: 600, ttl: 60_000 } })
  async balanceChanges(
    @Headers('authorization') authorization: unknown,
    @Headers('requestid') requestId: unknown,
    @Body() body: BidvBalanceChangesDto,
    @Response({ passthrough: true }) response: ExpressResponse,
  ) {
    response.setHeader('Cache-Control', 'no-store');
    const principal = await this.oauth.authenticateBearer(authorization);
    return this.ingress.ingest(principal, requestId, body.bankCode, body.data);
  }
}

@Controller('admin/api-connections/bidv')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature(FEATURE_KEYS.ADMIN_API_CONNECTIONS)
export class BidvH2hAdminController {
  constructor(private readonly admin: BidvH2hAdminService) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  snapshot(@Request() request: any) {
    return this.admin.snapshot(request.user);
  }

  @Post('clients')
  @Header('Cache-Control', 'no-store')
  createClient(@Request() request: any, @Body() body: CreateBankApiClientDto) {
    return this.admin.createClient(request.user, body.displayName);
  }

  @Post('clients/:id/rotate')
  @Header('Cache-Control', 'no-store')
  rotateClient(@Request() request: any, @Param('id') id: string) {
    return this.admin.rotateClient(request.user, id);
  }

  @Post('clients/:id/revoke')
  @Header('Cache-Control', 'no-store')
  revokeClient(
    @Request() request: any,
    @Param('id') id: string,
    @Body() body: RevokeBankConnectionDto,
  ) {
    return this.admin.revokeClient(request.user, id, body.recoveryOverride);
  }

  @Post('keys/generate')
  @Header('Cache-Control', 'no-store')
  generateKey(@Request() request: any, @Body() body: GenerateBankPgpKeyDto) {
    return this.admin.generateKey(request.user, body.displayName);
  }

  @Post('keys/import')
  @Header('Cache-Control', 'no-store')
  importKey(@Request() request: any, @Body() body: ImportBankPgpKeyDto) {
    return this.admin.importKey(request.user, body);
  }

  @Post('keys/:id/rotate')
  @Header('Cache-Control', 'no-store')
  rotateKey(@Request() request: any, @Param('id') id: string) {
    return this.admin.rotateKey(request.user, id);
  }

  @Post('keys/:id/revoke')
  @Header('Cache-Control', 'no-store')
  revokeKey(
    @Request() request: any,
    @Param('id') id: string,
    @Body() body: RevokeBankConnectionDto,
  ) {
    return this.admin.revokeKey(request.user, id, body.recoveryOverride);
  }

  @Get('keys/:id/public')
  @Header('Cache-Control', 'no-store')
  exportPublicKey(@Request() request: any, @Param('id') id: string) {
    return this.admin.exportPublicKey(request.user, id);
  }

  @Post('controls')
  @Header('Cache-Control', 'no-store')
  updateControl(
    @Request() request: any,
    @Body() body: UpdateBankConnectionControlDto,
  ) {
    return this.admin.updateControl(request.user, body);
  }
}
