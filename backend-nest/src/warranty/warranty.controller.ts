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

@Controller('warranties')
@UseGuards(AuthGuard('jwt'))
export class WarrantyController {
  constructor(private readonly warrantyService: WarrantyService) {}

  // POST /warranties — create (called after image upload)
  @Post()
  async create(@Request() req: any, @Body() body: any) {
    return this.warrantyService.createWarranty(req.user.id, body);
  }

  // GET /warranties — list all
  @Get()
  async findAll() {
    return this.warrantyService.getAllWarranties();
  }

  // GET /warranties/search?receipt=xxxxx
  @Get('search')
  async search(@Query('receipt') receipt: string) {
    return this.warrantyService.searchByReceipt(receipt || '');
  }

  // GET /warranties/detail?receipt=xxxxx
  @Get('detail')
  async getDetail(@Query('receipt') receipt: string) {
    return this.warrantyService.getByReceipt(receipt);
  }

  // GET /warranties/:id
  @Get(':id')
  async findOne(@Param('id') id: string) {
    return this.warrantyService.getWarrantyById(id);
  }

  // PUT /warranties/:id/status — update status, broadcasts via Redis -> Go -> WebSocket
  @Put(':id/status')
  async updateStatus(
    @Request() req: any,
    @Param('id') id: string,
    @Body('status') status: string,
  ) {
    return this.warrantyService.updateWarrantyStatus(
      id,
      req.user.id,
      status as any,
    );
  }
}
