export type RequestLogInput = {
  path?: unknown;
  originalUrl?: unknown;
  url?: unknown;
};

export function requestPathForLog(req: RequestLogInput): string {
  const rawPath =
    firstText(req.path) ?? firstText(req.originalUrl) ?? firstText(req.url);
  if (!rawPath) return '/';
  return rawPath.split('?')[0] || '/';
}

function firstText(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}
