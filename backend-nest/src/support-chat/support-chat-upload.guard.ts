import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { SupportChatService } from './support-chat.service';

@Injectable()
export class SupportChatRequesterUploadGuard implements CanActivate {
  constructor(private readonly supportChat: SupportChatService) {}

  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    this.supportChat.assertImageUploadAllowed(request.user, false);
    return true;
  }
}

@Injectable()
export class SupportChatAdminUploadGuard implements CanActivate {
  constructor(private readonly supportChat: SupportChatService) {}

  canActivate(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    this.supportChat.assertImageUploadAllowed(request.user, true);
    return true;
  }
}
