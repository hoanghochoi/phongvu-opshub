import { hash } from 'bcrypt';
import { BidvH2hOauthService } from './bidv-h2h-oauth.service';

describe('BidvH2hOauthService', () => {
  const accessTokenCreate = jest.fn();
  const clientFindUnique = jest.fn();
  const tokenFindUnique = jest.fn();
  const prisma = {
    bankApiClient: { findUnique: clientFindUnique },
    bankAccessToken: {
      create: accessTokenCreate,
      findUnique: tokenFindUnique,
    },
  } as any;
  const service = new BidvH2hOauthService(prisma);

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.BIDV_H2H_TOKEN_TTL_SECONDS = '300';
  });

  it('issues an opaque token and stores only its hash', async () => {
    clientFindUnique.mockResolvedValue({
      id: 'client-row-1',
      clientId: 'bidv_client',
      secretHash: await hash('secret-value', 4),
      bankCode: 'BIDV',
      scope: 'balance-changes:write',
      status: 'ACTIVE',
      revokedAt: null,
      overlapExpiresAt: null,
    });
    accessTokenCreate.mockResolvedValue({ id: 'token-row-1' });

    const response = await service.issueToken(
      `Basic ${Buffer.from('bidv_client:secret-value').toString('base64')}`,
    );
    expect(response.access_token).toBeTruthy();
    expect(response.expires_in).toBe(300);
    const stored = accessTokenCreate.mock.calls[0][0].data;
    expect(stored.tokenHash).toHaveLength(64);
    expect(stored.tokenHash).not.toBe(response.access_token);
    expect(JSON.stringify(stored)).not.toContain('secret-value');
  });

  it('returns a generic error for malformed or incorrect client auth', async () => {
    clientFindUnique.mockResolvedValue(null);
    await expect(service.issueToken('Basic invalid')).rejects.toMatchObject({
      response: expect.objectContaining({ error: 'invalid_client' }),
    });
  });

  it('rejects a client from another bank or without the fixed BIDV scope', async () => {
    clientFindUnique.mockResolvedValue({
      id: 'other-bank-client',
      clientId: 'shared_client',
      secretHash: await hash('secret-value', 4),
      bankCode: 'OTHER',
      scope: 'balance-changes:write',
      status: 'ACTIVE',
      revokedAt: null,
      overlapExpiresAt: null,
    });

    await expect(
      service.issueToken(
        `Basic ${Buffer.from('shared_client:secret-value').toString('base64')}`,
      ),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ error: 'invalid_client' }),
    });
    expect(accessTokenCreate).not.toHaveBeenCalled();
  });

  it('checks token, scope and current client state on every push', async () => {
    tokenFindUnique.mockResolvedValue({
      tokenHash: 'hash',
      scope: 'balance-changes:write',
      expiresAt: new Date(Date.now() + 60_000),
      revokedAt: null,
      client: {
        id: 'client-row-1',
        clientId: 'bidv_client',
        bankCode: 'BIDV',
        status: 'REVOKED',
        revokedAt: new Date(),
      },
    });
    await expect(
      service.authenticateBearer('Bearer opaque'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ error: 'invalid_token' }),
    });
  });

  it('rejects a valid-looking bearer token owned by another bank', async () => {
    tokenFindUnique.mockResolvedValue({
      tokenHash: 'hash',
      scope: 'balance-changes:write',
      expiresAt: new Date(Date.now() + 60_000),
      revokedAt: null,
      client: {
        id: 'other-bank-client',
        clientId: 'shared_client',
        bankCode: 'OTHER',
        status: 'ACTIVE',
        revokedAt: null,
      },
    });

    await expect(
      service.authenticateBearer('Bearer opaque'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({ error: 'invalid_token' }),
    });
  });
});
