import { Body, Controller, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { SearchMapVietinTransactionsDto } from './map-vietin.dto';
import { MapVietinService } from './map-vietin.service';

@Controller('admin/map-vietin')
@UseGuards(AuthGuard('jwt'))
export class MapVietinController {
  constructor(private readonly mapVietinService: MapVietinService) {}

  @Post('transactions/search')
  searchTransactions(
    @Request() req: any,
    @Body() body: SearchMapVietinTransactionsDto,
  ) {
    return this.mapVietinService.searchTransactions(req.user, body);
  }
}
