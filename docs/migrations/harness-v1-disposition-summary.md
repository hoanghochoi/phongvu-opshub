# Legacy Harness disposition summary

This sanitized report covers the schema-12 archive. Raw SQLite payloads,
notes, traces, absolute paths and downloaded binaries remain local-only. No
row is imported into upstream schema 14.

## Source and ledger

- Repository revision: `6525b6e3805eb666a86066cfe98469d5dba4af53`.
- Source database SHA-256: `7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`.
- Logical state SHA-256: `2633654f87c15fee6c143a14fa3138a7448c4204f4e24902dadff149583a78fd`.
- Expected records: intake 92, story 37, decision 7, backlog 27, trace 36 (199 total).
- Current disposition: `already-authoritative` 41, `superseded` 2,
  `linear-follow-up` 27, `historical-only` 129.
- Ledger SHA-256: `aa1d2dcef48d5761861dac058cc521f7e9f97a915d0aa70cbdfcffacea3d2a00`.
- Archive copies are local and may share a physical disk; this is not an off-host backup.

The disposition ledger ([harness-v1-disposition.json](harness-v1-disposition.json))
is deterministic and payload-free. Every source record
appears exactly once, identified by entity/id and a payload digest. Current Git
authority is referenced by repository-relative path; open follow-up work is
deduplicated to the existing Linear child issues listed in
`harness-v1-linear-targets.json`.

## Rules

- Stories and accepted decisions map to current Git authority only when the
  target exists. Protocol-v1 decisions map to ADR 0029 as `superseded`.
- Backlog rows map to a deduplicated Linear child issue; no one-file-per-row
  Markdown mirror is created.
- Intakes and traces are `historical-only`; their raw evidence remains in the
  local archive.
- Invalid prose is never promoted to a path contract or executable command.

The machine-readable ledger and archive manifest are the reviewable evidence;
this summary is not a replacement for product docs, ADRs, plans or Linear
acceptance criteria.
