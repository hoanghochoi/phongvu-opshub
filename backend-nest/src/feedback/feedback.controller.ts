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

@Controller('feedback')
@UseGuards(AuthGuard('jwt'))
export class FeedbackController {
  constructor(private readonly feedbackService: FeedbackService) {}

  @Post()
  @UseInterceptors(FilesInterceptor('images', 10, imageUploadOptions))
  async create(
    @Request() req: any,
    @Body()
    body: {
      content?: string;
      function?: string;
      description?: string;
      rating?: number;
    },
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

  @Get()
  async getAll() {
    return this.feedbackService.getAll();
  }
}
