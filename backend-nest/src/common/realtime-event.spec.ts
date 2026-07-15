import { buildRealtimeRedisEnvelope } from './realtime-event';

describe('buildRealtimeRedisEnvelope', () => {
  it('builds a strict, normalized server-routed envelope', () => {
    expect(
      buildRealtimeRedisEnvelope({
        type: 'payment_notification',
        eventId: ' payment:event-1 ',
        occurredAt: new Date('2026-07-15T03:00:00.000Z'),
        audience: {
          storeCodes: [' cp01 ', 'CP01'],
          recipientUserIds: [' user-1 ', 'user-1'],
          roles: ['super_admin'],
          departmentCodes: [' fin_acc '],
          organizationAccessCodes: ['acc'],
          policyCodes: [' payment_monitor_all_scope '],
          featureCodes: ['payment_monitor'],
        },
        payload: { notificationId: 'note-1' },
      }),
    ).toEqual({
      schemaVersion: 1,
      type: 'PAYMENT_NOTIFICATION',
      eventId: 'payment:event-1',
      occurredAt: '2026-07-15T03:00:00.000Z',
      audience: {
        storeCodes: ['CP01'],
        recipientUserIds: ['user-1'],
        roles: ['SUPER_ADMIN'],
        departmentCodes: ['FIN_ACC'],
        organizationAccessCodes: ['ACC'],
        policyCodes: ['PAYMENT_MONITOR_ALL_SCOPE'],
        featureCodes: ['PAYMENT_MONITOR'],
      },
      payload: { notificationId: 'note-1' },
    });
  });

  it('keeps policy selectors separate from organization codes', () => {
    const result = buildRealtimeRedisEnvelope({
      type: 'PAYMENT_NOTIFICATION',
      audience: { policyCodes: ['PAYMENT_MONITOR_ALL_SCOPE'] },
      payload: { notificationId: 'note-1' },
    });

    expect(result.audience.policyCodes).toEqual(['PAYMENT_MONITOR_ALL_SCOPE']);
    expect(result.audience.organizationAccessCodes).toEqual([]);
  });

  it('rejects feature-only routing to prevent accidental broad delivery', () => {
    expect(() =>
      buildRealtimeRedisEnvelope({
        type: 'PAYMENT_NOTIFICATION',
        audience: { featureCodes: ['PAYMENT_MONITOR'] },
        payload: { notificationId: 'note-1' },
      }),
    ).toThrow('server-derived audience');
  });

  it('generates a bounded unique event id when one is not supplied', () => {
    const result = buildRealtimeRedisEnvelope({
      type: 'WARRANTY_EVENT',
      audience: { roles: ['SUPER_ADMIN'] },
      payload: { warrantyId: 'warranty-1' },
    });

    expect(result.eventId).toMatch(
      /^warranty_event:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(result.eventId.length).toBeLessThanOrEqual(128);
  });
});
