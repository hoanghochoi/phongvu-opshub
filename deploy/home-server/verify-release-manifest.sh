#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 1 ] || { echo 'Usage: verify-release-manifest.sh <release>' >&2; exit 64; }
release="$(readlink -f "$1")"
[ -d "$release" ] || { echo 'Release manifest verification: release is unavailable' >&2; exit 1; }

python3 - "$release" <<'PY'
import hashlib, json, pathlib, re, sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest_path = root / 'release-manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
source = str(manifest.get('sourceCommit') or '')
if not re.fullmatch(r'[0-9a-f]{40}', source):
    raise SystemExit('Release manifest verification: invalid sourceCommit')
if not root.name.startswith(source + '-'):
    raise SystemExit('Release manifest verification: directory SHA differs from sourceCommit')
entries = manifest.get('files')
if not isinstance(entries, list) or not entries:
    raise SystemExit('Release manifest verification: files[] is missing')
seen = set()
for entry in entries:
    rel = str(entry.get('path') or '')
    if not rel or rel in seen or rel.startswith('/') or '\\' in rel:
        raise SystemExit('Release manifest verification: unsafe or duplicate path')
    seen.add(rel)
    path = (root / rel).resolve()
    try:
        path.relative_to(root)
    except ValueError:
        raise SystemExit('Release manifest verification: path escaped release root')
    if not path.is_file() or path.stat().st_size != entry.get('bytes'):
        raise SystemExit(f'Release manifest verification: size mismatch for {rel}')
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != entry.get('sha256'):
        raise SystemExit(f'Release manifest verification: sha256 mismatch for {rel}')
required = {
    'deploy/home-server/docker-compose.home.yml',
    'deploy/home-server/Caddyfile',
    'deploy/home-server/release-transaction.sh',
    'backend-nest/Dockerfile',
    'backend-go/Dockerfile',
}
missing = sorted(required - seen)
if missing:
    raise SystemExit('Release manifest verification: critical paths missing: ' + ','.join(missing))
print(source)
PY
