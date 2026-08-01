import { HEADERS_METADATA, HTTP_CODE_METADATA } from '@nestjs/common/constants';
import { THROTTLER_LIMIT } from '@nestjs/throttler/dist/throttler.constants';
import {
  BidvH2hAdminController,
  BidvH2hController,
} from './bidv-h2h.controller';

describe('BidvH2hController wire contract', () => {
  it('returns HTTP 200 for token and balance-change POST success', () => {
    expect(
      Reflect.getMetadata(
        HTTP_CODE_METADATA,
        BidvH2hController.prototype.token,
      ),
    ).toBe(200);
    expect(
      Reflect.getMetadata(
        HTTP_CODE_METADATA,
        BidvH2hController.prototype.balanceChanges,
      ),
    ).toBe(200);
  });

  it('uses dedicated trusted-IP quotas for the public bank endpoints', () => {
    expect(
      Reflect.getMetadata(
        `${THROTTLER_LIMIT}principal`,
        BidvH2hController.prototype.token,
      ),
    ).toBe(60);
    expect(
      Reflect.getMetadata(
        `${THROTTLER_LIMIT}principal`,
        BidvH2hController.prototype.balanceChanges,
      ),
    ).toBe(600);
  });

  it('marks every admin response as no-store', () => {
    const methods = [
      'snapshot',
      'createClient',
      'rotateClient',
      'revokeClient',
      'generateKey',
      'importKey',
      'rotateKey',
      'revokeKey',
      'exportPublicKey',
      'updateControl',
    ] as const;

    for (const method of methods) {
      expect(
        Reflect.getMetadata(
          HEADERS_METADATA,
          BidvH2hAdminController.prototype[method],
        ),
      ).toContainEqual({ name: 'Cache-Control', value: 'no-store' });
    }
  });
});
