import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { concatMap, dematerialize, materialize, Observable } from 'rxjs';
import { PrivateMediaService } from '../upload/private-media.service';

@Injectable()
export class SupportChatUploadCleanupInterceptor implements NestInterceptor {
  constructor(private readonly privateMedia: PrivateMediaService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    return next.handle().pipe(
      materialize(),
      concatMap(async (notification) => {
        const files = Array.isArray(request.files) ? request.files : [];
        await this.privateMedia.discardTemporaryFilesStrict(files);
        return notification;
      }),
      dematerialize(),
    );
  }
}
