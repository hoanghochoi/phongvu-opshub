import {
  Controller,
  Post,
  Body,
  UseGuards,
  Req,
  Logger,
  Optional,
} from '@nestjs/common';
import { SortService } from './sort.service';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { FifoCheckDto, SortCompletionReportDto, SortTextDto } from './sort.dto';
import { FifoService } from '../fifo/fifo.service';
import { logFingerprint } from '../common/log-sanitizer';

@Controller('sort')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class SortController {
  private readonly logger = new Logger(SortController.name);

  constructor(
    private readonly sortService: SortService,
    @Optional() private readonly fifoService?: FifoService,
  ) {}

  // POST /sort — body: { text: "SKU_OR_BIN" }
  // User email is extracted from JWT token, not from body
  @Post()
  @RequireFeature(FEATURE_KEYS.FIFO)
  async sort(@Req() req: any, @Body() body: SortTextDto) {
    const userEmail = req.user?.email || '';
    this.logger.log(
      `Sort request started: userId=${req.user?.id ?? 'unknown'} emailHash=${logFingerprint(userEmail)} inputHash=${logFingerprint(body.text)} inputLength=${body.text.length}`,
    );
    if (this.fifoService) {
      return this.fifoService.sort(req.user, { text: body.text });
    }
    const items = await this.sortService.sort(body.text, userEmail);
    return items;
  }

  // POST /sort/fifo-check — body: { text: "SKU_OR_SERIAL", qty?: number }
  // User email is extracted from JWT token, not from body
  @Post('fifo-check')
  @RequireFeature(FEATURE_KEYS.FIFO)
  async fifoCheck(@Req() req: any, @Body() body: FifoCheckDto) {
    const userEmail = req.user?.email || '';
    this.logger.log(
      `FIFO check started: userId=${req.user?.id ?? 'unknown'} emailHash=${logFingerprint(userEmail)} inputHash=${logFingerprint(body.text)} inputLength=${body.text.length} qty=${body.qty}`,
    );
    if (this.fifoService) {
      return this.fifoService.check(req.user, {
        text: body.text,
        includeExported: false,
      });
    }
    const result = await this.sortService.fifoCheck(
      body.text,
      body.qty,
      userEmail,
    );
    return result;
  }

  // POST /sort/completion-report — body: { sortedSKUs: [...] }
  @Post('completion-report')
  @RequireFeature(FEATURE_KEYS.FIFO)
  async completionReport(
    @Req() req: any,
    @Body() body: SortCompletionReportDto,
  ) {
    const userEmail = req.user?.email || '';
    this.logger.log(
      `Sort completion started: userId=${req.user?.id ?? 'unknown'} emailHash=${logFingerprint(userEmail)} count=${body.sortedSKUs?.length ?? 0}`,
    );
    return this.sortService.completionReport(
      body.sortedSKUs ?? [],
      userEmail,
      body.timestamp,
    );
  }
}
