# Legacy Harness disposition summary

This is a sanitized migration summary for the schema-12 archive. Raw SQLite
payloads, notes, traces, absolute paths and downloaded binaries remain local
only. No row is imported into upstream schema 14.

## Ledger

- Source revision: `6525b6e3805eb666a86066cfe98469d5dba4af53`.
- Source database SHA-256: `7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`.
- Logical state SHA-256: `2633654f87c15fee6c143a14fa3138a7448c4204f4e24902dadff149583a78fd`.
- Ledger: [harness-v1-disposition.json](harness-v1-disposition.json), exactly 199 records.
- Archive manifest: [harness-v1-archive-manifest.json](harness-v1-archive-manifest.json).

All records are currently either `already-authoritative` (22) or
`historical-only` (177). The exporter intentionally does not invent Linear
targets from legacy prose. Phase 3 reviews the historical-only set and creates
deduplicated Linear follow-ups only where a current owner and actionable target
are confirmed.

## Entity handling

| Entity | Count | Initial disposition rule |
| --- | ---: | --- |
| intake | 92 | Historical operational intake; retain in local archive. |
| story | 37 | Existing valid Git contract is already-authoritative; otherwise require current-authority review. |
| decision | 7 | Existing valid ADR is already-authoritative; protocol-v1 decisions are reviewed against ADR 0029. |
| backlog | 27 | Do not create one Markdown file per row; deduplicate into Linear follow-up only after review. |
| trace | 36 | Historical execution evidence; retain in local archive. |

This summary is not a replacement for product docs, ADRs, active plans or
Linear acceptance criteria. It exists to make the archive boundary and the
remaining review work explicit and auditable.
