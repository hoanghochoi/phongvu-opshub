import {
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Request,
  Res,
  StreamableFile,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthGuard } from '@nestjs/passport';
import { createReadStream } from 'fs';
import type { Response } from 'express';
import { PrivateMediaService } from './private-media.service';

@Controller('media')
@UseGuards(AuthGuard('jwt'))
export class PrivateMediaController {
  constructor(private readonly privateMediaService: PrivateMediaService) {}

  @Get(':id')
  @Throttle({
    principal: { ttl: 60_000, limit: 180 },
  })
  async read(
    @Request() req: any,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Res({ passthrough: true }) response: Response,
  ) {
    const opened = await this.privateMediaService.openForUser(id, req.user);
    response.setHeader('Content-Type', opened.media.contentTypeVerified);
    response.setHeader('Content-Length', String(opened.size));
    response.setHeader('Cache-Control', 'private, no-store, max-age=0');
    response.setHeader('Pragma', 'no-cache');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; sandbox",
    );
    return new StreamableFile(createReadStream(opened.filePath));
  }
}
