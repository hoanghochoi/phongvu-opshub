import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import {
  getAllowedEmailDomains,
  isAllowedEmailDomain,
} from './email-domain-policy';

describe('email domain policy', () => {
  const originalEnv = process.env.EMAIL_DOMAIN_FILE;

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.EMAIL_DOMAIN_FILE;
    } else {
      process.env.EMAIL_DOMAIN_FILE = originalEnv;
    }
  });

  it('accepts built-in OpsHub domains when the configured file is missing', () => {
    process.env.EMAIL_DOMAIN_FILE = path.join(
      os.tmpdir(),
      `missing-domain-file-${Date.now()}.txt`,
    );

    expect(getAllowedEmailDomains()).toContain('acare.vn');
    expect(isAllowedEmailDomain('admin@acare.vn')).toBe(true);
  });

  it('keeps built-in domains when the configured file is stale', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'opshub-domain-'));
    const file = path.join(dir, 'email_domain.txt');
    fs.writeFileSync(file, 'phongvu.vn\nteko.vn\n', 'utf8');
    process.env.EMAIL_DOMAIN_FILE = file;

    expect(getAllowedEmailDomains()).toEqual(
      expect.arrayContaining(['phongvu.vn', 'teko.vn', 'acare.vn']),
    );
    expect(isAllowedEmailDomain('admin@acare.vn')).toBe(true);
  });
});
