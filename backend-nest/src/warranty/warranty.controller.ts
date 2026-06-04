import {
  Controller,
  Get,
  Post,
  Put,
  Body,
  Param,
  Query,
  UseGuards,
  Request,
} from '@nestjs/common';
import { WarrantyService } from './warranty.service';
import { AuthGuard } from '@nestjs/passport';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { CreateWarrantyDto, UpdateWarrantyStatusDto } from './warranty.dto';

@Controller('warranties')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
@RequireFeature(FEATURE_KEYS.WARRANTY)
export class WarrantyController {
  constructor(private readonly warrantyService: WarrantyService) {}

  // POST /warranties — create (called after image upload)
  @Post()
  async create(@Request() req: any, @Body() body: CreateWarrantyDto) {
    return this.warrantyService.createWarranty(req.user.id, body);
  }

  // GET /warranties — list all
  @Get()
  async findAll(@Request() req: any) {
    return this.warrantyService.getAllWarranties(req.user);
  }

  // GET /warranties/search?receipt=xxxxx
  @Get('search')
  async search(@Request() req: any, @Query('receipt') receipt: string) {
    return this.warrantyService.searchByReceipt(req.user, receipt || '');
  }

  // GET /warranties/detail?receipt=xxxxx
  @Get('detail')
  async getDetail(@Request() req: any, @Query('receipt') receipt: string) {
    return this.warrantyService.getByReceipt(req.user, receipt);
  }

  // GET /warranties/:id
  @Get(':id')
  async findOne(@Request() req: any, @Param('id') id: string) {
    return this.warrantyService.getWarrantyById(req.user, id);
  }

  // PUT /warranties/:id/status — update status, broadcasts via Redis -> Go -> WebSocket
  @Put(':id/status')
  async updateStatus(
    @Request() req: any,
    @Param('id') id: string,
    @Body() body: UpdateWarrantyStatusDto,
  ) {
    return this.warrantyService.updateWarrantyStatus(
      req.user,
      id,
      req.user.id,
      body.status,
    );
  }
}
