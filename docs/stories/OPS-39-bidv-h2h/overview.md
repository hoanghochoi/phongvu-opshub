# OPS-39 - BIDV H2H balance changes

## Acceptance

- Dedicated UAT/production hosts expose only token, push and health.
- Secrets/tokens are verifier/hash-only; private PGP armor uses the dedicated
  KEK and is never returned.
- Valid batches commit receipt, canonical rows and outbox atomically; valid
  duplicates are stable and mixed-invalid batches write nothing.
- Operating mode migrates fail-closed to `STOPPED`; `UAT_INGEST_ONLY` accepts
  canonical data without projection and `LIVE` enables projection. Legacy
  boolean controls remain synchronized during the compatibility window.
- Projection defaults off and only Credit/VND/integer/unique-showroom rows
  enter existing payment consumers exactly once. A showroom candidate comes
  only from the exact `remark` suffix `<storeId> BOT` or `<storeId>` and must
  match one existing showroom. This restriction applies only to BIDV H2H;
  existing MAP/Vietin account/VA mapping remains unchanged.
- Super Admin manages clients and keys; the new three-state visual control is
  blocked until an exact approved Figma revision/node map exists.
- Operational runbooks, bank playbook, PDF and generator are stored only in
  ignored `output/bidv-private/` and are excluded from promotion.

Protected existing consumers: Tiền vào, Sao kê, VietQR, speaker, realtime,
Home, BigQuery, staff auth/throttling, Admin routes and the public OpsHub host.
The executable guard is `node scripts/validate-ops39-affected-consumers.mjs`.
