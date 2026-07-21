# OPS-8 Validation

## Automated Proof

Run from the repository root:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter compact
flutter build web --release --no-pub --no-web-resources-cdn --dart-define=APP_ENV=smoke
node scripts/patch-flutter-web-cache-busting.mjs ops8-proof
node scripts/verify-flutter-web-bootstrap.mjs ops8-proof
```

The verifier requires:

- all Flutter bootstrap template tokens in the source file;
- `canvasKitVariant: 'full'` in source and generated bootstrap files;
- resolved generated tokens;
- cache-busted bootstrap and Dart entrypoint URLs; and
- a non-empty `build/web/canvaskit/canvaskit.wasm` artifact.

## Chrome Proof

Serve `build/web` from a fresh local origin, enable the Chrome DevTools
`Audits` domain before navigation, and open `/#/login`. The accepted result is:

- page title `PhongVu OpsHub`;
- zero `DeprecationIssue` records of type `IntlV8BreakIterator`;
- CanvasKit resources under `/canvaskit/`, with no `/chromium/` segment; and
- `main.dart.js?v=ops8-proof` loaded successfully.

Local API CORS or WebSocket errors from an untrusted loopback origin are outside
this bootstrap proof; any engine, script-load, or CanvasKit error is a failure.

## Affected Runtime Proof

Harness intake `85` maps the bootstrap, cache-busting script, verifier, product
contract, story packet, and test matrix to story `OPS-8`. Final evidence must be
recorded with strict affected-runtime run and check commands from the same
Windows-native Git Bash execution backend used at intake.
