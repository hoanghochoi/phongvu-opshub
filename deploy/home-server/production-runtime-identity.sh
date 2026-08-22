#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo 'Usage: production-runtime-identity.sh <write|verify> <record> <release> <env> <downloads> <web> <current-link>' >&2
  exit 64
fi
action="$1" record="$2" release="$(readlink -f "$3")" env_file="$4" downloads="$5" web="$6" current_link="$7"
compose_file="$release/deploy/home-server/docker-compose.home.yml"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(readlink -f "$current_link" || true)" = "$release" ] || { echo 'Runtime identity: current pointer differs from release' >&2; exit 1; }
source_commit="$(bash "$script_dir/verify-release-manifest.sh" "$release")"
compose=(docker compose --project-name home-server --env-file "$env_file" -f "$compose_file")
compose_cmd() { OPSHUB_ENV_FILE="$env_file" "${compose[@]}" "$@" < /dev/null; }

container_image() {
  local service="$1" container
  container="$(compose_cmd ps -q "$service")"
  [ -n "$container" ] || return 1
  docker inspect --format '{{.Image}}' "$container"
}
hash_path() { sha256sum "$1" | awk '{print $1}'; }
hash_tree() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys

root = pathlib.Path(sys.argv[1])
if not root.is_dir() or not (root / 'index.html').is_file():
    raise SystemExit('Runtime identity: web tree or index.html is missing')

tree = hashlib.sha256()
for path in sorted(root.rglob('*'), key=lambda item: item.relative_to(root).as_posix()):
    if path.is_symlink():
        raise SystemExit(f'Runtime identity: web tree contains a symlink: {path.relative_to(root).as_posix()}')
    if path.is_dir():
        continue
    if not path.is_file():
        raise SystemExit(f'Runtime identity: web tree contains an unsupported entry: {path.relative_to(root).as_posix()}')
    content = hashlib.sha256()
    size = 0
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            size += len(chunk)
            content.update(chunk)
    fields = (
        path.relative_to(root).as_posix().encode('utf-8'),
        str(size).encode('ascii'),
        content.hexdigest().encode('ascii'),
    )
    for field in fields:
        tree.update(len(field).to_bytes(8, 'big'))
        tree.update(field)
print(tree.hexdigest())
PY
}
help_hash="$(find "$downloads/help" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | awk '{print $1}')"
api_image="$(container_image api)"
realtime_image="$(container_image realtime)"
caddy_hash="$(compose_cmd exec -T caddy sha256sum /etc/caddy/Caddyfile | awk '{print $1}')"

candidate="$(mktemp)"
trap 'rm -f "$candidate"' EXIT
python3 - "$candidate" "$source_commit" "$(hash_path "$env_file")" "$api_image" "$realtime_image" \
  "$caddy_hash" "$(hash_tree "$web")" "$(hash_path "$downloads/latest.json")" "$help_hash" <<'PY'
import json, pathlib, sys
keys = ('sourceCommit','envSha256','apiImageId','realtimeImageId','caddySha256','webSha256','manifestSha256','helpSha256')
pathlib.Path(sys.argv[1]).write_text(json.dumps(dict(zip(keys, sys.argv[2:])), sort_keys=True) + '\n', encoding='utf-8')
PY

case "$action" in
  write)
    install -d -m 0700 "$(dirname "$record")"
    install -m 0600 "$candidate" "${record}.next"
    mv -Tf "${record}.next" "$record"
    echo 'Protected production runtime identity recorded.'
    ;;
  verify)
    [ -s "$record" ] && cmp -s "$candidate" "$record" || { echo 'Protected production runtime identity is missing or stale.' >&2; exit 1; }
    echo 'Protected production runtime identity verified.'
    ;;
  *) echo 'Runtime identity: unsupported action' >&2; exit 64 ;;
esac
