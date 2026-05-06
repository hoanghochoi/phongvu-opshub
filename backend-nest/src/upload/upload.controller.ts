import {
  Controller,
  Post,
  UploadedFiles,
  UseInterceptors,
  Body,
  UseGuards,
  Req,
} from '@nestjs/common';
import { FilesInterceptor } from '@nestjs/platform-express';
import { AuthGuard } from '@nestjs/passport';
import { UploadService } from './upload.service';
import { imageUploadOptions } from './image-upload.options';

@Controller('upload')
@UseGuards(AuthGuard('jwt'))
export class UploadController {
  constructor(private readonly uploadService: UploadService) {}

  // POST /upload/warranty
  // Multipart: fields: { receipt, user } + files: image0, image1, ...
  @Post('warranty')
  @UseInterceptors(FilesInterceptor('images', 10, imageUploadOptions))
  async uploadWarrantyImages(
    @Req() req: any,
    @Body() body: { receipt: string },
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    const links = await this.uploadService.saveWarrantyImages(
      body.receipt,
      files || [],
    );
    await this.uploadService.upsertWarrantyRecord(
      body.receipt,
      links,
      req.user.id,
    );
    return {
      status: 'success',
      receipt: body.receipt,
      links,
      links_str: this.uploadService.getLinksString(links),
    };
  }
}
