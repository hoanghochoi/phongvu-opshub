#!/usr/bin/env bash
set -euo pipefail

: "${CURRENT_DIR:?CURRENT_DIR is required}"
: "${OPSHUB_ENV_FILE:?OPSHUB_ENV_FILE is required}"
: "${DOWNLOADS_DIR:?DOWNLOADS_DIR is required}"
: "${WEB_DIR:?WEB_DIR is required}"

run_privileged() {
  if [[ -n "${OPSHUB_SUDO-sudo}" ]]; then
    "${OPSHUB_SUDO-sudo}" "$@"
  else
    "$@"
  fi
}

digest_file() {
  local path="$1"
  if run_privileged test -f "$path"; then
    run_privileged sha256sum -- "$path" | awk '{print $1}'
  else
    printf 'MISSING\n'
  fi
}

digest_tree() {
  local path="$1"
  if ! run_privileged test -d "$path"; then
    printf 'MISSING\n'
    return
  fi

  run_privileged bash -c '
    set -euo pipefail
    root="$1"
    cd "$root"
    record() {
      local rel="$1" type mode uid gid content
      type="$(stat -c %F -- "$rel")"
      mode="$(stat -c %a -- "$rel")"
      uid="$(stat -c %u -- "$rel")"
      gid="$(stat -c %g -- "$rel")"
      case "$type" in
        "regular file") content="$(sha256sum -- "$rel" | awk "{print \$1}")" ;;
        "symbolic link") content="$(readlink -- "$rel")" ;;
        *) content="-" ;;
      esac
      printf "%s\\0%s\\0%s\\0%s\\0%s\\0%s\\0" "$rel" "$type" "$mode" "$uid" "$gid" "$content"
    }
    record .
    while IFS= read -r -d "" rel; do
      record "$rel"
    done < <(find . -mindepth 1 -printf "%P\\0" | LC_ALL=C sort -z)
  ' bash "$path" | sha256sum | awk '{print $1}'
}

digest_client_files() {
  if ! run_privileged test -d "$DOWNLOADS_DIR"; then
    printf 'MISSING\n'
    return
  fi

  run_privileged bash -c '
    set -euo pipefail
    root="$1"
    cd "$root"
    while IFS= read -r -d "" rel; do
      type="$(stat -c %F -- "$rel")"
      mode="$(stat -c %a -- "$rel")"
      uid="$(stat -c %u -- "$rel")"
      gid="$(stat -c %g -- "$rel")"
      content="$(sha256sum -- "$rel" | awk "{print \$1}")"
      printf "%s\\0%s\\0%s\\0%s\\0%s\\0" "$rel" "$type" "$mode" "$uid" "$gid" "$content"
    done < <(
      find . -maxdepth 1 -type f \
        \( -name "phongvu-opshub-v*.apk" \
           -o -name "phongvu-opshub-staging-v*.apk" \
           -o -name "phongvu-opshub-windows-v*.zip" \
           -o -name "phongvu-opshub-staging-windows-v*.zip" \
           -o -name "phongvu-opshub-windows-setup-v*.exe" \
           -o -name "phongvu-opshub-staging-windows-setup-v*.exe" \
           -o -name "phongvu-opshub-windows-v*.sha256" \
           -o -name "phongvu-opshub-staging-windows-v*.sha256" \) \
        -printf "%P\\0" | LC_ALL=C sort -z
    )
  ' bash "$DOWNLOADS_DIR" | sha256sum | awk '{print $1}'
}

current_release="$(readlink -f "$CURRENT_DIR" || true)"
[[ -n "$current_release" && -d "$current_release" ]] || {
  echo 'Current staging release is unavailable.' >&2
  exit 1
}

printf 'current_release=%s\n' "$current_release"
printf 'env_sha256=%s\n' "$(digest_file "$OPSHUB_ENV_FILE")"
printf 'web_tree_sha256=%s\n' "$(digest_tree "$WEB_DIR")"
printf 'download_help_tree_sha256=%s\n' "$(digest_tree "$DOWNLOADS_DIR/help")"
printf 'runtime_help_tree_sha256=%s\n' "$(digest_tree "$current_release/docs/help")"
printf 'caddyfile_sha256=%s\n' "$(digest_file "$current_release/deploy/home-server/Caddyfile")"
printf 'manifest_sha256=%s\n' "$(digest_file "$DOWNLOADS_DIR/latest.json")"
printf 'download_page_sha256=%s\n' "$(digest_file "$DOWNLOADS_DIR/download.html")"
printf 'download_icon_sha256=%s\n' "$(digest_file "$DOWNLOADS_DIR/opshub-icon-192.png")"
printf 'client_files_sha256=%s\n' "$(digest_client_files)"
