# OPS-53 — Redesign Chrome audit and follow-up consolidation

## Status

`active` — Linear OPS-53 remains `In Progress`. Nine execution fragments were
consolidated into history files under `docs/plans/completed/`; this is the one
current execution summary and next-action authority.

## Owner, scope and next action

- Owner: OPS-53 UI/UX audit owner, coordinated with OPS-44 release owner.
- Scope: approved responsive shell, Home filters/overview, command controls,
  FIFO result cards and Quick Actions, Follow-up filters, Sales Report cards,
  employee filter, dialogs and remaining route/state findings.
- Next action: publish/merge any still-unpublished bounded corrections, deploy
  the exact merge SHA to staging, and run the authenticated Light/Dark Chrome
  matrix plus required Android/Windows checks. Do not close OPS-53 from local
  proof or a staging merge alone.

## Current visual authority

All visual edits use an exact approved Figma node and a recorded node map before
the first production edit. The consolidated waves retain these authorities:

| Wave | Approved authority | Protected consumers |
| --- | --- | --- |
| Home inline filters/overview and iOS PWA corrections | `2201:61216`, `2213:152953` | Home scope/date, intrinsic overview, auth shell, Sales command row |
| Home residual shell and Quick Actions | `2190:151155`, `2190:151217`, `406:16778`, `2331:2325` | Home shell, compact launcher, notifications, profile dialog |
| Shared command controls | `2222:82`, `2219:2`, `2219:76` | Follow-up, FIFO Check/Sort, Warranty and Sales filters |
| FIFO result-card/layout | `2285:64848`, `2288:23647`, `2289:23723`, `2305:56165` | FIFO ordering, inventory metadata, export and permissions |
| Follow-up scoped filters | `2231:63150` | status/search/date/showroom/category, realtime and pagination |
| Sales Report clickable/employee cards | `2357:65013`, `2357:65029`, `2357:65035`, `380:7977`, `1874:130010` | report-form callback, employee identity and authorized scope |

The full node maps, exact geometry, copy and local proof remain in the
corresponding history files. History is evidence, not a second current policy.
Product/runtime rules remain in `docs/product/`, `docs/ui-redesign/` and the
OPS-44 handoff.

## Shipped and verified scope

- The bounded fragments have local characterization/geometry proof and retain
  affected-provider/API/permission tests.
- Shared controls use the canonical DateRangePicker, command-input row,
  Vietnamese-first copy and Phosphor icon mapping; no runtime `Icons.*` path
  is reintroduced.
- Local analyzer, focused/full Flutter proof, relevant Nest proof and release
  builds are recorded per fragment. Those results do not claim deployed visual
  completion.

## Residual gaps and stop conditions

- Any changed visual state without an exact approved node stops the slice until
  Figma authority is updated and read back.
- Staging proof must identify the exact deployed SHA and cover
  `375×812`, `834×1112`, `1024×768` and `1440×900` in Light and Dark, with
  route/state evidence and no console errors or horizontal clipping.
- Product behavior, API/DTO, permission, platform and security contracts must
  remain unchanged. A visual delta is a failing proof, not a reason to accept
  a fallback.
- OPS-53 and OPS-44 remain open until their release/QA and production gates
  are satisfied.

## Recovery

Revert only the bounded correction commit through `staging`. Keep the history
files and disposition ledger so no Figma decision or residual gap is lost.
