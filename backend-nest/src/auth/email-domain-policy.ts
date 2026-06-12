import * as fs from 'fs';
import * as path from 'path';

const DEFAULT_DOMAIN_FILE = 'data/email_domain.txt';
const DOMAIN_FILE_KEY = 'EMAIL_DOMAIN_FILE';
const DEFAULT_ALLOWED_DOMAINS = [
  'phongvu.vn',
  'acare.vn',
];

function normalizeDomain(domain: string): string {
  return domain.trim().replace(/^@/, '').toLowerCase();
}

function parseDomainList(raw: string): string[] {
  return raw
    .split(/[\r\n,]+/)
    .map(normalizeDomain)
    .filter(Boolean);
}

function getCandidateFiles(): string[] {
  const configured = process.env[DOMAIN_FILE_KEY]?.trim();
  const candidates = [
    configured,
    path.resolve(process.cwd(), DEFAULT_DOMAIN_FILE),
    path.resolve(process.cwd(), '..', DEFAULT_DOMAIN_FILE),
  ];

  return candidates.filter((file): file is string => Boolean(file));
}

export function getAllowedEmailDomains(): string[] {
  for (const file of getCandidateFiles()) {
    if (fs.existsSync(file)) {
      const domains = parseDomainList(fs.readFileSync(file, 'utf8'));
      if (domains.length > 0) return withDefaultDomains(domains);
    }
  }

  return DEFAULT_ALLOWED_DOMAINS;
}

export function isAllowedEmailDomain(email: string): boolean {
  const emailDomain = email.split('@')[1]?.toLowerCase();
  return Boolean(
    emailDomain &&
    getAllowedEmailDomains().includes(normalizeDomain(emailDomain)),
  );
}

export function allowedEmailDomainMessage(): string {
  return 'Chỉ chấp nhận email thuộc domain OpsHub cho phép';
}

function withDefaultDomains(domains: string[]): string[] {
  return Array.from(new Set([...domains, ...DEFAULT_ALLOWED_DOMAINS]));
}
