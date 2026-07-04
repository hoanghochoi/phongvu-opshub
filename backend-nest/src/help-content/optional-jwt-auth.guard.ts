import {
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser = any>(
    err: any,
    user: any,
    info: any,
    context: ExecutionContext,
    _status?: any,
  ): TUser {
    const request = context.switchToHttp().getRequest();
    const authHeader = request?.headers?.authorization;
    if (!authHeader) {
      return null as TUser;
    }
    if (err) {
      throw err;
    }
    if (info) {
      throw new UnauthorizedException();
    }
    return (user ?? null) as TUser;
  }
}
