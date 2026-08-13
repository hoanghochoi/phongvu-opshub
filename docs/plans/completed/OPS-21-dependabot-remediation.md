# Execution Plan: OPS-21 Dependabot Remediation

Date: 2026-07-24

## Status

Active

## Outcome

Close Dependabot alerts #23-#26 by removing every vulnerable
`@hono/node-server`, `fast-uri`, and `sharp` release from the NestJS dependency
graph while preserving Prisma tooling, private-media upload processing, and
server-rendered VietQR PNG output.

## Context

- Linear: OPS-21 tracks GitHub Dependabot alerts #23-#26.
- Stable checkpoint captured twice before edits:
  - branch `codex/ops-21-fix-dependabot-23-26`;
  - HEAD `d488571fdf526d3fd5d7c1778408b905289412f9`;
  - clean worktree/index;
  - `backend-nest/package.json` blob
    `48198d131131f4c9ef7856a51df31d8bf82b84e5`;
  - `backend-nest/package-lock.json` blob
    `d7c5ef70c5026fc1581b3334023261c503db325a`.
- Baseline dependency paths:
  - `sharp@0.34.5` is a direct runtime dependency used by private-media image
    normalization and server-side VietQR PNG composition;
  - `fast-uri@3.1.2` is transitive through AJV in Nest CLI/Webpack and Prisma
    development tooling;
  - `prisma@7.8.0 -> @prisma/dev@0.24.3 -> @hono/node-server@1.19.13` is a
    development-only CLI path pinned by an existing override.
- Product authority: `docs/product/warranty.md` requires upload image behavior
  to remain intact; `docs/product/vietqr.md` requires the external API to keep
  returning a valid server-rendered PNG.

## Patch Contract

- Vulnerable components and boundaries:
  - Sharp inherits libvips vulnerabilities and processes user-supplied upload
    bytes through `PrivateMediaService.normalizeImage`; generated VietQR SVG,
    QR, and logo buffers also pass through Sharp.
  - Fast-uri host-confusion advisories affect URI parsing reached through AJV
    tooling dependencies; no direct OpsHub runtime caller is established.
  - The Hono Windows static-file traversal affects Prisma development tooling;
    OpsHub does not import Hono directly.
- Security invariants:
  - no installed `sharp <0.35.0`;
  - no installed `fast-uri <3.1.4`;
  - no installed `@hono/node-server <2.0.5` (prefer removing the dependency by
    upgrading Prisma over forcing an incompatible Hono major override);
  - `npm audit` and production-only audit report zero vulnerabilities.
- Compatibility to preserve:
  - valid upload images normalize and persist with verified image metadata;
  - spoofed/invalid image bytes remain rejected before metadata creation;
  - VietQR external rendering returns a decodable PNG containing the expected
    QR payload;
  - Prisma schema validation, client generation, Nest build, and migrations
    remain buildable on the repository's Node 22 runtime.

## Scope

In scope:

- Replace Prisma's vulnerable development-tooling package with the compatible
  fixed patch from the same `@prisma/dev` series while retaining the aligned
  Prisma 7.8 runtime/client packages.
- Upgrade Sharp to a fixed 0.35.x release supported by Node 22.
- Refresh all admitted fast-uri lockfile copies to 3.1.4 or newer.
- Remove the obsolete Hono override when the dependency path disappears.
- Add proof only where existing affected-consumer coverage is insufficient.
- Record exact security and regression results in `docs/TEST_MATRIX.md` and
  Linear.

Out of scope:

- Broad dependency updates, forced audit fixes, Dependabot dismissal, unrelated
  refactors, ruleset changes, production promotion, or Linear `Done`.

## Approach

1. Update Sharp to 0.35.x, replace the obsolete Hono override with the fixed
   `@prisma/dev@0.24.16` tooling patch, and perform a package-lock-only install
   while retaining aligned Prisma 7.8 runtime/client packages.
2. Refresh fast-uri within existing parent ranges and reject unrelated lockfile
   churn after inspecting every changed package.
3. Install exactly from the resulting lockfile and validate the dependency tree,
   Prisma CLI/schema/client generation, Sharp upload handling, and VietQR PNG
   rendering.
4. Run both npm audit modes, focused affected-consumer Jest, Nest build, full
   Jest, Docker runtime image proof when available, and final diff checks.
5. Record proof, publish a reviewed PR to `staging`, observe staging deployment,
   perform staging QA, and leave OPS-21 at `Ready for Release` only when those
   gates pass.
6. After staging exposed a baseline-CPU incompatibility in Sharp's Linux x64
   prebuilt addon, compile the Sharp 0.35.3 addon from source in the Alpine
   build stage, retain its libvips 8.18.3 runtime dependency, and require real
   PNG proof both before and after production-dependency pruning.
7. Restore ERR-trap inheritance in the staging runtime transaction so a future
   failure inside a Compose helper invokes the already-checkpointed automatic
   rollback instead of leaving the failed release active.

## Risks And Recovery

- Sharp 0.35 changes native libvips packaging or image behavior: keep the direct
  upgrade isolated, run real-buffer upload and PNG decode tests, and revert the
  manifest/lockfile pair if compatibility fails.
- The Prisma dev-tooling override could be incompatible with the pinned CLI:
  require schema validation, client generation, build, and full Jest before
  accepting it.
- A lock refresh may pull unrelated packages: inspect and narrow the generated
  diff rather than accepting broad churn.
- Docker may be unavailable locally: CI/staging image build remains mandatory;
  any local gap is recorded as unknown until that proof passes.
- Staging's QEMU baseline CPU lacks x86-64-v2/SSE4.2 and cannot use Sharp's
  Linux x64 prebuilt addon or its Wasm SIMD fallback: build the native addon
  with the image toolchain, prove the resulting image on that exact host, and
  keep the previous healthy release as the recovery target until QA passes.
- Recovery before publication is to revert only the OPS-21 worktree changes;
  after merge, use the repository revert-through-staging workflow.

## Progress

- [x] Create OPS-21, finish the OPS-19 lifecycle, and start a clean task
      worktree from live `origin/staging`.
- [x] Capture a stable pre-edit checkpoint and map advisory/dependency paths.
- [x] Apply the minimal manifest and lockfile remediation.
- [x] Run ordered local security closure and affected-consumer validation.
- [x] Update durable local proof and complete the pre-publication diff review.
- [x] Publish PR #32 and pass PR CI; diagnose its staging runtime failure and
      restore the previous healthy release through the audited checkpoint.
- [x] Prove the source-built, production-pruned Sharp artifact on the exact
      staging CPU and restore inherited ERR-trap rollback coverage.
- [ ] Publish the follow-up PR, pass staging deployment/QA, and hand off at
      `Ready for Release`.

## Decisions

- 2026-07-24: Treat the work as high-risk maintenance because Sharp processes
  user-controlled runtime image bytes and the package manifest is a runtime
  artifact.
- 2026-07-24: Prefer replacing Prisma's internal `@prisma/dev` package with
  fixed same-series `0.24.16` over overriding `@hono/node-server` across a
  major version.
- 2026-07-24: Use Sharp 0.35.3 rather than the first fixed 0.35.0 because npm's
  current remediation selects 0.35.3 and it supports the Node `>=20.9.0`
  contract satisfied by the Node 22 Docker image.
- 2026-07-24: Use fast-uri 3.1.4 as the floor because it closes both active
  advisories; 3.1.3 closes only alert #24.
- 2026-07-24: A trial Prisma 7.9.0 lock refresh removed Hono but introduced
  `@prisma/dev@0.24.14`, which is affected by a newly published
  `find-my-way <=9.6.0` HTTP/2 denial-of-service advisory and caused broad
  Prisma Studio/engine churn. Retain Prisma 7.8.0 and override only its
  development-tooling package to `@prisma/dev@0.24.16` (which uses
  `find-my-way@9.7.0`), then prove CLI compatibility.
- 2026-07-24: Do not downgrade Sharp or bypass its CPU guard. Staging run
  `30107168348` confirmed that the prebuilt addon requires x86-64-v2 while the
  host exposes a baseline QEMU CPU; compile the same fixed Sharp/libvips release
  from source and make the Docker build exercise the exact pruned artifact.
- 2026-07-24: The same run proved the remote deployment's ERR trap was not
  inherited inside shell functions. Enable Bash errtrace (`set -E`) and guard
  it in the platform-security verifier; retain the explicit post-deploy
  rollback step for failures after the runtime transaction succeeds.

## Validation

- Applicability/buildability:
  - `npm ci`
  - `npx prisma validate`
  - `npx prisma generate`
  - `npm run build`
- Security closure:
  - `npm ls fast-uri sharp @hono/node-server @prisma/dev prisma --all`
  - scripted version-floor assertions against `package-lock.json`
  - `npm audit`
  - `npm audit --omit=dev`
- Protected existing consumers:
  - `src/upload/private-media.service.spec.ts`
  - the real PNG/QR decode case in `src/vietqr/vietqr.service.spec.ts`
  - full `npm test -- --runInBand`
- Runtime artifact/repository checks:
  - production dependency tree;
  - `docker build` for `backend-nest/Dockerfile` when available;
  - exact final diff review and `git diff --check`.

## Result

The local changeset upgrades Sharp to `0.35.3`/libvips `8.18.3`, refreshes all
fast-uri paths to `3.1.4`, removes vulnerable Hono Node Server, and replaces its
Prisma dev-tooling override with fixed `@prisma/dev@0.24.16` and
`find-my-way@9.7.0` while keeping Prisma runtime/client packages at `7.8.0`.

The repeatable security verifier passed version-floor assertions and exploit
regressions for fast-uri IDN/backslash parsing, inherited HTTP methods in
find-my-way, and a real Sharp PNG encode/decode control. Final-lock local proof
passed `npm ci`, Prisma validate/generate, Nest build, both npm audit modes with
zero vulnerabilities, focused private-media/VietQR Jest (2 suites/35 tests),
and full Jest (89 suites/873 tests). ESLint does not include standalone `.mjs`
scripts in its TypeScript project service, so the new verifier is covered by
Node syntax execution and Prettier instead. Local Docker proof is unavailable
because the Docker Desktop Linux daemon is not running; PR CI, staging image
build/deploy, and staging QA remain mandatory before release readiness.

PR #32 merged as `b3be3486d0f94c482e8fb4b1d82365073c5e3ab8`, but staging
run `30107168348` failed when the API loaded Sharp on a CPU without
x86-64-v2/SSE4.2; the Wasm fallback also required unsupported Wasm SIMD. The
audited rollback restored release `d488571f...-30098775176-1`, public health,
version metadata, and all service health checks. Follow-up runtime proof is now
required before the remediation can advance.

The follow-up runtime image built successfully on the exact staging host. Both
the full-dependency build gate and production-pruned layer loaded Sharp 0.35.3
with libvips 8.18.3 and completed real PNG encode/decode. The isolated final
image probe ran as UID 1000, reported the source addon as `x64v2=false`, found
no missing dynamic libraries, and confirmed that compiler, node-gyp, and
libvips headers were absent. Local regression proof also remained green:
focused 2 suites/35 tests, full 89 suites/873 tests, Nest build, Prisma
validate/generate, both audit modes, platform security checks, release workflow
tests, workflow YAML parsing, and `git diff --check`.
