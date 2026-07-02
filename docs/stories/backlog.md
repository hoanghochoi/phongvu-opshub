# Story Backlog

Seed backlog for future OpsHub work. Convert an item into a story packet when
implementation starts.

| Candidate | Domain | Notes |
| --- | --- | --- |
| Document exact auth session contract | Auth | Token lifetime, refresh, logout, allowed domain |
| Add API contract examples for mobile repositories | Backend | Request/response samples for Flutter integration |
| Add warranty upload smoke checklist | Warranty | Camera, picker, upload, image URL, realtime update |
| Add FIFO history authorization story | FIFO/Auth | Clarify who can view admin history |
| Add local validation script | Platform | One command for Flutter, NestJS, and Go checks |
| Fix FIFO Windows render blocker and define desktop layout contract | UX/UI | Follow up from `docs/ux-ui-audit-2026-05-25.md`; first address FIFO infinite-width search button, then standardize PC spacing/grid |
| Evaluate paid Windows code signing or managed allow-list deployment | Platform | Follow-up only if internal self-signed trust plus checksum rollout is not enough; WINDOWS-DIST-001 keeps unsigned direct downloads as a documented fallback risk |
| Resolve Figma Data Workspace route gap | UX/UI | Figma includes Data Workspace, but repo has no routed runtime screen; define product contract before implementation |
| Resolve Figma generic Report Workspace route gap | UX/UI | Decide whether Figma Report Workspace becomes a real report hub or merges into existing Sales Report surfaces |
| Expose Personnel Catalog Admin when approved | Admin/UX | Code screen exists but is not in router/menu; needs permission proof and UX review before exposing |
| Decide FIFO Conversation Check route fate | FIFO/UX | Code screen exists but is not exposed; confirm active workflow or retire before adding navigation |
