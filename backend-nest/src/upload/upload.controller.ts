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
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { UploadService } from './upload.service';
import { imageUploadOptions } from './image-upload.options';
import { UploadWarrantyImagesDto } from './upload.dto';

@Controller('upload')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class UploadController {
  constructor(private readonly uploadService: UploadService) {}

  // POST /upload/warranty
  // Multipart: fields: { receipt, user } + files: image0, image1, ...
  @Post('warranty')
  @RequireFeature(FEATURE_KEYS.WARRANTY)
  @UseInterceptors(FilesInterceptor('images', 10, imageUploadOptions))
  async uploadWarrantyImages(
    @Req() req: any,
    @Body() body: UploadWarrantyImagesDto,
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
