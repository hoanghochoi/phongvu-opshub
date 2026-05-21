import {
  Body,
  Controller,
  Get,
  Post,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import {
  ListStoredMapVietinTransactionsDto,
  SearchMapVietinTransactionsDto,
} from './map-vietin.dto';
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

  @Get('transactions')
  listStoredTransactions(
    @Request() req: any,
    @Query() query: ListStoredMapVietinTransactionsDto,
  ) {
    return this.mapVietinService.listStoredTransactions(req.user, query);
  }
}
