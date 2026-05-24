# Scripts

This folder contains project validation or maintenance scripts plus the OpsHub
Harness durable-layer entrypoint.

## Harness CLI

Use `scripts/harness` to record and query structured harness state:

```bash
scripts/harness init
scripts/harness import brownfield
scripts/harness intake ...
scripts/harness story add ...
scripts/harness story update ...
scripts/harness decision add ...
scripts/harness backlog add ...
scripts/harness trace ...
scripts/harness query matrix
```

The schema lives in `scripts/schema/`. The generated database files
`harness.db`, `harness.db-wal`, and `harness.db-shm` are local runtime state and
must not be committed.

The CLI can delegate to a prebuilt Rust binary at `scripts/bin/harness-cli` when
present, but OpsHub keeps that binary local and ignored. Without the binary, the
repo-local shell wrapper works through `sqlite3`. On Windows PowerShell, run the
entrypoint through bash, for example `bash scripts/harness query matrix`; the
wrapper also falls back to `sqlite3.exe` when that is the available binary.

Current validation commands are documented in `AGENTS.md` and
`docs/TEST_MATRIX.md`. If a command becomes repeated and stable, add a script
here and update the harness docs.
