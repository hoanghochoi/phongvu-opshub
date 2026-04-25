import { Controller, Post, Body, UseGuards, Req, Logger } from '@nestjs/common';
import { SortService } from './sort.service';
import { AuthGuard } from '@nestjs/passport';

@Controller('sort')
@UseGuards(AuthGuard('jwt'))
export class SortController {
  private readonly logger = new Logger(SortController.name);

  constructor(private readonly sortService: SortService) {}

  // POST /sort — body: { text: "SKU_OR_BIN" }
  // User email is extracted from JWT token, not from body
  @Post()
  async sort(@Req() req: any, @Body() body: { text: string }) {
    const userEmail = req.user?.email || '';
    this.logger.log(`[SORT] text="${body.text}" user="${userEmail}"`);
    const items = await this.sortService.sort(body.text, userEmail);
    return items;
  }

  // POST /sort/fifo-check — body: { text: "SKU_OR_SERIAL", qty?: number }
  // User email is extracted from JWT token, not from body
  @Post('fifo-check')
  async fifoCheck(
    @Req() req: any,
    @Body() body: { text: string; qty?: number },
  ) {
    const userEmail = req.user?.email || '';
    this.logger.log(
      `[FIFO-CHECK] text="${body.text}" qty=${body.qty} user="${userEmail}"`,
    );
    const result = await this.sortService.fifoCheck(
      body.text,
      body.qty,
      userEmail,
    );
    return result;
  }

  // POST /sort/completion-report — body: { sortedSKUs: [...] }
  @Post('completion-report')
  async completionReport(
    @Req() req: any,
    @Body() body: { sortedSKUs: any[]; timestamp?: string },
  ) {
    const userEmail = req.user?.email || '';
    this.logger.log(
      `[SORT-COMPLETION] user="${userEmail}" count=${body.sortedSKUs?.length ?? 0}`,
    );
    return this.sortService.completionReport(
      body.sortedSKUs ?? [],
      userEmail,
      body.timestamp,
    );
  }
}
