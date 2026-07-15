import { randomUUID } from 'crypto';

export type RealtimeEventAudienceInput = {
  storeCodes?: unknown[];
  recipientUserIds?: unknown[];
  roles?: unknown[];
  departmentCodes?: unknown[];
  organizationAccessCodes?: unknown[];
  policyCodes?: unknown[];
  featureCodes?: unknown[];
};

export type RealtimeRedisEnvelope<TPayload extends Record<string, unknown>> = {
  schemaVersion: 1;
  type: string;
  eventId: string;
  occurredAt: string;
  audience: {
    storeCodes: string[];
    recipientUserIds: string[];
    roles: string[];
    departmentCodes: string[];
    organizationAccessCodes: string[];
    policyCodes: string[];
    featureCodes: string[];
  };
  payload: TPayload;
};

export function buildRealtimeRedisEnvelope<
  TPayload extends Record<string, unknown>,
>(input: {
  type: string;
  eventId?: string;
  occurredAt?: Date | string;
  audience: RealtimeEventAudienceInput;
  payload: TPayload;
}): RealtimeRedisEnvelope<TPayload> {
  const type = normalizeCode(input.type);
  if (!type) throw new Error('Realtime event type is required');

  const occurredAtDate =
    input.occurredAt instanceof Date
      ? input.occurredAt
      : input.occurredAt
        ? new Date(input.occurredAt)
        : new Date();
  if (Number.isNaN(occurredAtDate.getTime())) {
    throw new Error('Realtime event occurredAt is invalid');
  }

  const eventId = String(
    input.eventId || `${type.toLowerCase()}:${randomUUID()}`,
  ).trim();
  if (!eventId || eventId.length > 128) {
    throw new Error('Realtime event id is invalid');
  }
  if (
    !input.payload ||
    typeof input.payload !== 'object' ||
    Array.isArray(input.payload)
  ) {
    throw new Error('Realtime event payload must be an object');
  }

  const audience = {
    storeCodes: normalizeCodes(input.audience.storeCodes),
    recipientUserIds: normalizeIds(input.audience.recipientUserIds),
    roles: normalizeCodes(input.audience.roles),
    departmentCodes: normalizeCodes(input.audience.departmentCodes),
    organizationAccessCodes: normalizeCodes(
      input.audience.organizationAccessCodes,
    ),
    policyCodes: normalizeCodes(input.audience.policyCodes),
    featureCodes: normalizeCodes(input.audience.featureCodes),
  };
  const hasRoutingSelector =
    audience.storeCodes.length > 0 ||
    audience.recipientUserIds.length > 0 ||
    audience.roles.length > 0 ||
    audience.departmentCodes.length > 0 ||
    audience.organizationAccessCodes.length > 0 ||
    audience.policyCodes.length > 0;
  if (!hasRoutingSelector) {
    throw new Error('Realtime event requires a server-derived audience');
  }

  return {
    schemaVersion: 1,
    type,
    eventId,
    occurredAt: occurredAtDate.toISOString(),
    audience,
    payload: input.payload,
  };
}

function normalizeCodes(values: unknown[] | undefined) {
  return normalizeValues(values, true);
}

function normalizeIds(values: unknown[] | undefined) {
  return normalizeValues(values, false);
}

function normalizeValues(values: unknown[] | undefined, uppercase: boolean) {
  const normalized: string[] = [];
  const seen = new Set<string>();
  for (const value of values ?? []) {
    const text = String(value ?? '').trim();
    const candidate = uppercase ? text.toUpperCase() : text;
    if (!candidate || seen.has(candidate)) continue;
    seen.add(candidate);
    normalized.push(candidate);
  }
  return normalized;
}

function normalizeCode(value: unknown) {
  return String(value ?? '')
    .trim()
    .toUpperCase();
}
