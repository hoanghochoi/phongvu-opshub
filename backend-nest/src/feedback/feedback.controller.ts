import {
  Controller,
  Post,
  Get,
  Body,
  UseGuards,
  Request,
  UploadedFiles,
  UseInterceptors,
} from '@nestjs/common';
import { FeedbackService } from './feedback.service';
import { AuthGuard } from '@nestjs/passport';
import { FilesInterceptor } from '@nestjs/platform-express';
import { imageUploadOptions } from '../upload/image-upload.options';
import { FEATURE_KEYS } from '../feature/feature.constants';
import { RequireFeature } from '../feature/feature.decorator';
import { FeatureGuard } from '../feature/feature.guard';
import { CreateFeedbackDto } from './feedback.dto';

@Controller('feedback')
@UseGuards(AuthGuard('jwt'), FeatureGuard)
export class FeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Post()
  @RequireFeature(FEATURE_KEYS.FEEDBACK)
  @UseInterceptors(FilesInterceptor('images', 10, imageUploadOptions))
  async create(
    @Request() req: any,
    @Body() body: CreateFeedbackDto,
    @UploadedFiles() files: Express.Multer.File[] = [],
  ) {
    return this.feedbackService.create(
      req.user.id,
      {
        content: body.content,
        functionName: body.function,
        description: body.description,
        rating: body.rating ?? 5,
      },
      files,
    );
  }

  @Get('admin')
  @RequireFeature(FEATURE_KEYS.ADMIN_FEEDBACK)
  async getAll(@Request() req: any) {
    return this.feedbackService.getAll(req.user);
  }
}
