# OPS-78 Opt-in blue/green topology harness

This slice is a deployment-model contract and dry-run harness. It is not a
traffic switch, migration runner, load test or production authorization.

## What the overlay provides

`deploy/home-server/docker-compose.blue-green.yml` is loaded only together
with the base compose file and the `bluegreen-candidate` profile. It starts a
color-specific API/realtime candidate on an isolated network, attaches shared
PostgreSQL/Redis to a pre-created external network, and publishes no host
ports. The existing single-plane API, realtime and Caddy services remain the
default/recovery path.

The edge fixture in `Caddyfile.bluegreen.template` is rendered only for
fingerprinted review. The helper never runs Docker, reloads Caddy, changes the
active release pointer, stops a service or switches traffic.

## Dry-run contract

From the repository root, create a sanitized plan with distinct active and
candidate release identifiers:

```text
node deploy/staging/blue-green-topology.mjs plan \
  --active-color blue \
  --candidate-color green \
  --active-release release-100 \
  --candidate-release release-101 \
  --output tmp/blue-green-plan.json
```

Render a candidate edge fixture without mutating the active Caddy config:

```text
node deploy/staging/blue-green-topology.mjs render \
  --color green \
  --output tmp/Caddyfile.green
```

Validate the sanitized plan before attaching it to a review or release
window:

```text
node deploy/staging/blue-green-topology.mjs validate \
  --manifest tmp/blue-green-plan.json
```

The plan must keep `trafficSwitch.allowed=false`,
`trafficSwitch.performed=false`, `migration.allowed=false` and
`migration.performed=false`. The rollback target is always the active release.
The generated files and any raw runtime output stay outside Git.

## Required later gates

Before any live candidate start, the next slice must prove the external shared
network exists, Compose config is valid, image/config digests are exact, the
candidate health and authenticated Home 1/7/30/90 parity gates pass, and the
old color remains healthy. A separate approved slice must then implement
atomic Caddy selection, new WebSocket routing, a bounded 120-second drain,
expand/contract migration proof, rollback and the release-window checkpoint.
Only after those gates may the existing staging load runbook create synthetic
users or execute the 100-QPS/60-socket profile. Any restart, write, migration
ambiguity, unexpected 429/5xx/timeout, parity mismatch, resource breach or
cleanup uncertainty is a fail-closed stop.
