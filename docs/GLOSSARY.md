# Glossary

| Term | Meaning |
| --- | --- |
| OpsHub | Internal Phong Vu operations app |
| FIFO | First-in, first-out inventory workflow |
| Sort | SKU grouping/sorting workflow |
| Warranty | Warranty or repair image capture and status flow |
| NestJS API | Backend service under `backend-nest/` |
| Realtime service | Go service under `backend-go/` that relays Redis events to WebSocket clients |
| Product contract | Accepted behavior documented under `docs/product/` |
| Story packet | Small implementation plan and evidence record under `docs/stories/` |
| Feature intake | Classification step that turns a prompt into tiny, normal, or high-risk work before implementation begins |
| Durable layer | Local SQLite database plus `scripts/harness` CLI that stores queryable operational records |
| Trace | Structured record of what an agent did during a task: actions, files, errors, outcome, and harness friction |
