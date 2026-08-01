import { lastValueFrom, of, throwError } from 'rxjs';
import { SupportChatUploadCleanupInterceptor } from './support-chat-upload-cleanup.interceptor';
import {
  SupportChatAdminUploadGuard,
  SupportChatRequesterUploadGuard,
} from './support-chat-upload.guard';

describe('Support Chat upload boundary', () => {
  const context = (request: any) =>
    ({
      switchToHttp: () => ({ getRequest: () => request }),
    }) as any;

  it('checks feature and requester identity before multipart parsing', () => {
    const service = { assertImageUploadAllowed: jest.fn() };
    const guard = new SupportChatRequesterUploadGuard(service as any);
    const user = { id: 'requester-1' };

    expect(guard.canActivate(context({ user }))).toBe(true);
    expect(service.assertImageUploadAllowed).toHaveBeenCalledWith(user, false);
  });

  it('checks feature and Super Admin role before admin multipart parsing', () => {
    const service = { assertImageUploadAllowed: jest.fn() };
    const guard = new SupportChatAdminUploadGuard(service as any);
    const user = { id: 'admin-1', role: 'SUPER_ADMIN' };

    expect(guard.canActivate(context({ user }))).toBe(true);
    expect(service.assertImageUploadAllowed).toHaveBeenCalledWith(user, true);
  });

  it('removes managed temporary files after a successful handler', async () => {
    const files = [{ path: 'managed-1' }];
    const media = {
      discardTemporaryFilesStrict: jest.fn().mockResolvedValue(undefined),
    };
    const interceptor = new SupportChatUploadCleanupInterceptor(media as any);

    await expect(
      lastValueFrom(
        interceptor.intercept(context({ files }), { handle: () => of('ok') }),
      ),
    ).resolves.toBe('ok');
    expect(media.discardTemporaryFilesStrict).toHaveBeenCalledWith(files);
  });

  it('removes managed temporary files after DTO, route or service failure', async () => {
    const files = [{ path: 'managed-2' }];
    const media = {
      discardTemporaryFilesStrict: jest.fn().mockResolvedValue(undefined),
    };
    const interceptor = new SupportChatUploadCleanupInterceptor(media as any);

    await expect(
      lastValueFrom(
        interceptor.intercept(context({ files }), {
          handle: () => throwError(() => new Error('invalid_request')),
        }),
      ),
    ).rejects.toThrow('invalid_request');
    expect(media.discardTemporaryFilesStrict).toHaveBeenCalledWith(files);
  });
});
