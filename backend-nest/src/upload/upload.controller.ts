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
import {
  IMAGE_UPLOAD_MAX_FILES,
  imageUploadOptions,
} from './image-upload.options';
import { UploadWarrantyImagesDto } from './upload.dto';
import { Throttle } from '@nestjs/throttler';

@Controller('upload')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class UploadController {
  constructor(private readonly uploadService: UploadService) {}

  // POST /upload/warranty
  // Multipart: fields: { receipt } + files: images[].
  // Legacy clients may still send "user"; it is accepted only for compatibility.
  // The creator is always resolved from the authenticated JWT user.
  @Post('warranty')
  @RequireFeature(FEATURE_KEYS.WARRANTY)
  @Throttle({
    ip: { ttl: 60_000, limit: 12 },
    principal: { ttl: 60_000, limit: 6 },
  })
  @UseInterceptors(
    FilesInterceptor('images', IMAGE_UPLOAD_MAX_FILES, imageUploadOptions),
  )
  async uploadWarrantyImages(
    @Req() req: any,
    @Body() body: UploadWarrantyImagesDto,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    const links = await this.uploadService.saveWarrantyImages(
      body.receipt,
      files || [],
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
