# SECURITY-001 Execution Plan

1. Capture checkpoint and record high-risk intake.
2. Add regression tests that reproduce the Critical/High findings.
3. Apply Wave 0 source/config mitigations: edge headers, query redaction,
   break-glass removal, staging credential removal, and safe log rotation.
4. Implement NestJS/Go/Flutter WebSocket ticket flow with a compatibility flag.
5. Implement server-side realtime audience enforcement and backpressure.
6. Implement private media dual-read, upload validation, and cutover tooling.
7. Apply auth, rate-limit, OTP, enumeration, CSV, app-log, VietQR, external URL,
   container, backup, Android, and local Compose hardening.
8. Upgrade safe dependencies; document replacements that require a dedicated
   compatibility corpus.
9. Remove only source/assets proven unreachable and minimize release artifacts.
10. Run focused tests after every workstream, then the full validation matrix.
11. Update the implementation checklist, validation evidence, TEST_MATRIX, and
    the manual action runbook.
12. Deploy to staging only after the local gate is green. Production promotion
    requires the same SHA/image digests and completion of manual security gates.

## Stop conditions

- A change touches the protected Sales Report diff without an unavoidable,
  reviewed reason.
- A rollback would reopen a Critical finding.
- Media authorization or realtime audience proof is missing.
- The full backend baseline has unexplained failures beyond the two checkpointed
  Sales Report tests.
- Runtime SHA/digest does not match the locally verified artifact.
