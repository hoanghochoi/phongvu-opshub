import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Request,
  Res,
  ServiceUnavailableException,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import type { Response } from 'express';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { VietQrService } from './vietqr.service';

@Controller('vietqr')
export class VietQrController {
  constructor(private readonly vietQrService: VietQrService) {}

  @Post()
  @UseGuards(AuthGuard('jwt'), FeatureGuard)
  @RequireFeature(FEATURE_KEYS.VIETQR)
  async create(
    @Request() req: any,
    @Body()
    body: {
      amount?: number | string | null;
      orderCode?: string;
      storeCode?: string;
    },
  ) {
    const rawAmount = body.amount;
    const amount =
      rawAmount === undefined || rawAmount === null || rawAmount === ''
        ? null
        : Number(rawAmount);

    return this.vietQrService.create({
      amount,
      orderCode: body.orderCode ?? '',
      storeCode: body.storeCode ?? '',
      createdById: req.user?.id,
      user: req.user,
    });
  }

  @Post(':id/confirm')
  @UseGuards(AuthGuard('jwt'), FeatureGuard)
  @RequireFeature(FEATURE_KEYS.VIETQR)
  async confirm(@Request() req: any, @Param('id') id: string) {
    return this.vietQrService.confirmPayment(req.user, id);
  }

  @Get('n8n')
  async createExternalFromQuery(@Request() req: any, @Query() query: any) {
    this.assertExternalAccess(req, query);
    return this.stripBinary(
      await this.vietQrService.createExternal(this.toExternalInput(query)),
    );
  }

  @Post('n8n')
  async createExternalFromBody(@Request() req: any, @Body() body: any) {
    this.assertExternalAccess(req, body);
    return this.stripBinary(
      await this.vietQrService.createExternal(this.toExternalInput(body)),
    );
  }

  @Get('n8n/status')
  async externalStatusFromQuery(@Request() req: any, @Query() query: any) {
    this.assertExternalAccess(req, query);
    return this.externalStatus(query);
  }

  @Post('n8n/status')
  async externalStatusFromBody(@Request() req: any, @Body() body: any) {
    this.assertExternalAccess(req, body);
    return this.externalStatus(body);
  }

  @Get('n8n/image')
  async createExternalImage(
    @Request() req: any,
    @Query() query: any,
    @Res() res: Response,
  ) {
    this.assertExternalAccess(req, query);
    const result = await this.vietQrService.createExternal(
      this.toExternalInput(query),
    );

    res.setHeader('Content-Type', result.imageMimeType);
    res.setHeader(
      'Content-Disposition',
      `inline; filename="${result.imageFileName}"`,
    );
    res.setHeader('X-OpsHub-Payment-Id', result.paymentId);
    res.setHeader('X-OpsHub-Bank-Name', result.bankName);
    res.setHeader('X-OpsHub-Account-Number', result.accountNumber);
    res.setHeader('X-OpsHub-Account-Name', result.accountName);
    res.setHeader('X-OpsHub-Amount', result.amount?.toString() ?? '');
    res.setHeader('X-OpsHub-Transfer-Content', result.transferContent);
    res.setHeader('X-OpsHub-Brand-Key', result.qrBrand.key);
    res.setHeader('X-OpsHub-Brand-Title', result.qrBrand.title);
    res.send(result.imageBuffer);
  }

  private assertExternalAccess(req: any, raw: Record<string, unknown>) {
    const expected = process.env.VIETQR_EXTERNAL_API_KEY?.trim();
    if (!expected) {
      throw new ServiceUnavailableException(
        'Chưa cấu hình API key VietQR cho n8n',
      );
    }

    const authorization = this.firstHeader(req, 'authorization');
    const bearerToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
    const provided =
      this.firstHeader(req, 'x-opshub-vietqr-key') ||
      bearerToken ||
      this.firstText(raw.apiKey) ||
      this.firstText(raw.key);

    if (provided !== expected) {
      throw new UnauthorizedException('API key VietQR không hợp lệ');
    }
  }

  private toExternalInput(raw: Record<string, unknown>) {
    return {
      amount: this.parseAmount(raw.amount),
      orderCode: this.firstText(raw.orderCode, raw.order_code, raw.order),
      transferContent: this.firstText(
        raw.transferContent,
        raw.addInfo,
        raw.add_info,
        raw.content,
      ),
      addInfo: this.firstText(raw.addInfo, raw.add_info),
      storeCode: this.firstText(raw.storeCode, raw.store_code, raw.store) ?? '',
      source: this.firstText(raw.source) ?? 'n8n',
    };
  }

  private stripBinary(
    result: Awaited<ReturnType<VietQrService['createExternal']>>,
  ) {
    const { imageBuffer, ...json } = result;
    return json;
  }

  private externalStatus(raw: Record<string, unknown>) {
    const paymentId = this.firstText(raw.paymentId, raw.payment_id, raw.id);
    if (this.isTruthy(raw.check) || this.isTruthy(raw.confirm)) {
      return this.vietQrService.checkExternalStatus(paymentId ?? '');
    }
    return this.vietQrService.getExternalStatus(paymentId ?? '');
  }

  private parseAmount(value: unknown): number | null {
    if (value === undefined || value === null || value === '') return null;
    if (typeof value === 'number') return value;
    const normalized = String(value).replace(/[^0-9]/g, '');
    return normalized ? Number(normalized) : null;
  }

  private firstHeader(req: any, name: string): string | null {
    const value = req.headers?.[name] ?? req.headers?.[name.toLowerCase()];
    return this.firstText(Array.isArray(value) ? value[0] : value);
  }

  private firstText(...values: unknown[]): string | null {
    for (const value of values) {
      if (value === undefined || value === null) continue;
      const normalized = String(value).trim();
      if (normalized) return normalized;
    }
    return null;
  }

  private isTruthy(value: unknown): boolean {
    if (typeof value === 'boolean') return value;
    if (value === undefined || value === null) return false;
    return ['1', 'true', 'yes', 'y'].includes(
      String(value).trim().toLowerCase(),
    );
  }
}
