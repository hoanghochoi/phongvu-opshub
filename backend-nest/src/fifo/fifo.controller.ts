import { Body, Controller, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FifoCheckDto, FifoExportDto } from './fifo.dto';
import { FifoService } from './fifo.service';

@Controller('fifo')
@UseGuards(AuthGuard('jwt'))
export class FifoController {
  constructor(private readonly fifoService: FifoService) {}

  @Post('check')
  check(@Req() req: any, @Body() body: FifoCheckDto) {
    return this.fifoService.check(req.user, body);
  }

  @Post('export')
  export(@Req() req: any, @Body() body: FifoExportDto) {
    return this.fifoService.setExported(req.user, body);
  }
}
