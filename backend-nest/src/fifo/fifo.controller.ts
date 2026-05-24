import {
  Body,
  Controller,
  Post,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { FileInterceptor } from '@nestjs/platform-express';
import { FifoCheckDto, FifoExportDto } from './fifo.dto';
import { FifoService } from './fifo.service';
import { inventoryFileUploadOptions } from './inventory-file-upload.options';
import { ManualInventoryParserService } from './manual-inventory-parser.service';

@Controller('fifo')
@UseGuards(AuthGuard('jwt'))
export class FifoController {
  constructor(
    private readonly fifoService: FifoService,
    private readonly parser: ManualInventoryParserService,
  ) {}

  @Post('check')
  check(@Req() req: any, @Body() body: FifoCheckDto) {
    return this.fifoService.check(req.user, body);
  }

  @Post('export')
  export(@Req() req: any, @Body() body: FifoExportDto) {
    return this.fifoService.setExported(req.user, body);
  }

  @Post('inventory/import')
  @UseInterceptors(FileInterceptor('file', inventoryFileUploadOptions))
  importInventory(@Req() req: any, @UploadedFile() file: Express.Multer.File) {
    const parsed = this.parser.parse(file);
    return this.fifoService.importManualInventory(req.user, parsed.items, {
      fileName: file?.originalname,
      totalRows: parsed.totalRows,
      skippedRows: parsed.skippedRows,
    });
  }
}
