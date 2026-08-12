# OPS-53 — FIFO result card R2

## Checkpoint

- Branch: `codex/ops-53-fifo-result-card-r2`
- Worktree: `opshub-ops-53-fifo-result-card-r2`
- Base: `c06a6de6b668c726046e4d199f138f1b46321652` (exact
  `origin/staging` at lifecycle start)
- Intake state: clean.

## Goal and boundaries

Implement the approved FIFO result-card and pill revisions while preserving
FIFO ordering, permissions, scanner/search, export mutation, history and
provider behavior. No legacy visual fallback is retained for the serial result.

## Approved node map

| Viewport/state | Figma node | Flutter target |
| --- | --- | --- |
| Desktop wrong serial, 1440×900 | `2285:64848`, card `2285:65033` | `FifoCheckScreen` → desktop serial result body |
| Compact first viewport, 375×812 | `2288:23647`, card `2288:23705` | compact serial result body |
| Compact scrolled result | `2289:23723`, card `2289:23734` | same compact body after command area scrolls away |
| Shared mobile pill contract | `2305:56165` | `AppMetadataPill`, `AppActionPill`, `_FifoBadge` |

Visible mapping:

- Status accent: 8px desktop / 7px compact, semantic status color.
- Card: 1126×248 desktop; 343×316 compact first; 343×322 compact scrolled.
- Copy/status/metadata: `Sai FIFO` / `Đúng FIFO`; serial, SKU and location
  copy actions; import date, inventory age and BIN type static metadata.
- Desktop metadata: 40px pills, 20px icons, 14px label, 12px gaps.
- Compact metadata: four fixed 40px tracks; 30px visual pills, 12px label,
  14px icons, 10px visual vertical rhythm; action pills keep 48dp target.
- Compact export: 20px checkbox visual, 14/20 label, 8px gap, 40px visual row.
- Recent lookups: independent action pills that rerun the exact stored value.

## Data and protected behavior

The existing backend inventory model already owns `binType`; expose it as nullable
`bin_type` in the FIFO response and parse it in Flutter. FIFO rule/order,
inventory persistence and export behavior do not change. Copy logs remain
sanitized and do not include serial, SKU or email values.

## Verification

- [x] Format and targeted analyzer: no issues.
- [x] Focused Flutter FIFO redesign suite: 15/15 passed, including
  compact/desktop geometry and copy/export behaviors.
- [x] Focused Nest FIFO service suite: 14/14 passed, including `bin_type`
  response proof; Nest build passed.
- [x] `git diff --check` and local web release build passed; Wasm dry run
  succeeded.
- [ ] After staging deploy: authenticated Chrome comparison at 375×812 and
  1440×900 against the exact nodes above.
