# 0028 - Canonical bank ingress and managed H2H credentials

Status: accepted for OPS-39 local implementation, 2026-07-30.

OpsHub separates bank acceptance from legacy payment projection. Canonical
ingress completes without downstream systems; a leased worker translates only
eligible rows into `MapVietinTransaction`. Operations can stop payment side
effects while preserving safe bank receipt and audit.

H2H credentials use dedicated models, not `AdminSetting`. Secrets/tokens are
verifier/hash-only. Private OpenPGP material is AES-256-GCM envelope encrypted
under an environment-specific 32-byte KEK. Responses are redacted except for
one-time generated secrets and public keys.

The migration is expand-only. Old MAP/eFAST integer behavior remains, while
exact Decimal and bank metadata are additive. Multi-bank/multi-environment
administration is outside this decision.
