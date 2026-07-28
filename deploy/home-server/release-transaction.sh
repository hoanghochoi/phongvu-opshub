#!/usr/bin/env bash

# Shared, fail-closed filesystem transaction primitives for OpsHub publication.
# Callers provide the remote paths and keep service orchestration in the
# workflow so runtime health checks remain visible in CI logs.

opshub_txn_run() {
  if [[ -n "${OPSHUB_SUDO-sudo}" ]]; then
    "${OPSHUB_SUDO-sudo}" "$@"
  else
    "$@"
  fi
}

opshub_txn_die() {
  echo "OpsHub release transaction: $*" >&2
  return 1
}

opshub_txn_validate_id() {
  [[ "${DEPLOY_RUN_ID:-}" =~ ^[0-9]+$ ]] ||
    opshub_txn_die "invalid deploy run id"
  [[ "${DEPLOY_RUN_ATTEMPT:-}" =~ ^[1-9][0-9]*$ ]] ||
    opshub_txn_die "invalid deploy run attempt"
}

opshub_txn_begin() {
  : "${OPSHUB_ENV_FILE:?OPSHUB_ENV_FILE is required}"
  : "${OPSHUB_SSD_ROOT:?OPSHUB_SSD_ROOT is required}"
  : "${OPSHUB_REMOTE_APP_DIR:?OPSHUB_REMOTE_APP_DIR is required}"
  : "${CURRENT_DIR:?CURRENT_DIR is required}"
  : "${REMOTE_RELEASE_DIR:?REMOTE_RELEASE_DIR is required}"
  opshub_txn_validate_id

  OPSHUB_TXN_ID="${DEPLOY_RUN_ID}-${DEPLOY_RUN_ATTEMPT}"
  OPSHUB_TXN_ROLLBACK_DIR="${OPSHUB_SSD_ROOT}/rollback"
  OPSHUB_TXN_ENV_SNAPSHOT="${OPSHUB_ENV_FILE}.rollback.${OPSHUB_TXN_ID}"
  OPSHUB_TXN_STATE="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.state"
  OPSHUB_TXN_STATE_TMP="${OPSHUB_TXN_STATE}.tmp"
  OPSHUB_TXN_SHARED_SNAPSHOT="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.shared"
  OPSHUB_TXN_SHARED_STAGE="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.stage"

  local previous_current remote_release_real releases_dir
  previous_current="$(readlink -f "$CURRENT_DIR" || true)"
  remote_release_real="$(readlink -f "$REMOTE_RELEASE_DIR" || true)"
  releases_dir="$(readlink -f "${OPSHUB_REMOTE_APP_DIR}/releases" || true)"
  [[ -n "$previous_current" && -d "$previous_current" ]] ||
    opshub_txn_die "healthy previous release is required"
  if [[ "${OPSHUB_TXN_STATIC_ONLY:-false}" != true ]]; then
    [[ -n "$remote_release_real" && -d "$remote_release_real" ]] ||
      opshub_txn_die "candidate release is unavailable"
  else
    remote_release_real="$previous_current"
  fi
  case "$previous_current" in
    "$releases_dir"/*) ;;
    *) opshub_txn_die "previous release is outside protected releases directory" ;;
  esac
  if [[ "${OPSHUB_TXN_STATIC_ONLY:-false}" != true ]]; then
    case "$remote_release_real" in
      "$releases_dir"/*) ;;
      *) opshub_txn_die "candidate release is outside protected releases directory" ;;
    esac
  fi
  [[ ! -e "$OPSHUB_TXN_ENV_SNAPSHOT" && ! -e "$OPSHUB_TXN_STATE" &&
    ! -e "$OPSHUB_TXN_STATE_TMP" && ! -e "$OPSHUB_TXN_SHARED_SNAPSHOT" &&
    ! -e "$OPSHUB_TXN_SHARED_STAGE" ]] ||
    opshub_txn_die "rollback metadata already exists for this run"

  opshub_txn_run install -d -m 0700 "$OPSHUB_TXN_ROLLBACK_DIR"
  opshub_txn_run cp --preserve=mode,ownership,timestamps -- "$OPSHUB_ENV_FILE" "$OPSHUB_TXN_ENV_SNAPSHOT"
  printf '%s\n%s\n' "$previous_current" "$remote_release_real" |
    opshub_txn_run tee "$OPSHUB_TXN_STATE_TMP" >/dev/null
  opshub_txn_run chmod 0600 "$OPSHUB_TXN_STATE_TMP"
  opshub_txn_run mv -Tf -- "$OPSHUB_TXN_STATE_TMP" "$OPSHUB_TXN_STATE"
  export OPSHUB_TXN_ID OPSHUB_TXN_ROLLBACK_DIR OPSHUB_TXN_ENV_SNAPSHOT OPSHUB_TXN_STATE
  export OPSHUB_TXN_SHARED_SNAPSHOT OPSHUB_TXN_SHARED_STAGE
}

opshub_txn_load() {
  : "${OPSHUB_ENV_FILE:?OPSHUB_ENV_FILE is required}"
  : "${OPSHUB_SSD_ROOT:?OPSHUB_SSD_ROOT is required}"
  opshub_txn_validate_id
  OPSHUB_TXN_ID="${DEPLOY_RUN_ID}-${DEPLOY_RUN_ATTEMPT}"
  OPSHUB_TXN_ROLLBACK_DIR="${OPSHUB_SSD_ROOT}/rollback"
  OPSHUB_TXN_ENV_SNAPSHOT="${OPSHUB_ENV_FILE}.rollback.${OPSHUB_TXN_ID}"
  OPSHUB_TXN_STATE="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.state"
  OPSHUB_TXN_STATE_TMP="${OPSHUB_TXN_STATE}.tmp"
  OPSHUB_TXN_SHARED_SNAPSHOT="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.shared"
  OPSHUB_TXN_SHARED_STAGE="${OPSHUB_TXN_ROLLBACK_DIR}/deploy-${OPSHUB_TXN_ID}.stage"
  opshub_txn_run test -s "$OPSHUB_TXN_ENV_SNAPSHOT" || opshub_txn_die "env snapshot is unavailable"
  opshub_txn_run test -s "$OPSHUB_TXN_STATE" || opshub_txn_die "rollback state is unavailable"
  export OPSHUB_TXN_ID OPSHUB_TXN_ROLLBACK_DIR OPSHUB_TXN_ENV_SNAPSHOT OPSHUB_TXN_STATE
  export OPSHUB_TXN_SHARED_SNAPSHOT OPSHUB_TXN_SHARED_STAGE
}

opshub_txn_require_promoted() {
  : "${OPSHUB_TXN_SHARED_SNAPSHOT:?transaction not loaded}"
  opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/SNAPSHOT_READY" || {
    opshub_txn_die "shared snapshot is incomplete"
    return 1
  }
  opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/PROMOTED" || {
    opshub_txn_die "shared promotion is incomplete"
    return 1
  }
}

opshub_txn_snapshot_shared() {
  : "${DOWNLOADS_DIR:?DOWNLOADS_DIR is required}"
  : "${WEB_DIR:?WEB_DIR is required}"
  : "${OPSHUB_TXN_SHARED_SNAPSHOT:?transaction not started}"
  opshub_txn_run install -d -m 0700 \
    "$OPSHUB_TXN_SHARED_SNAPSHOT/downloads" \
    "$OPSHUB_TXN_SHARED_SNAPSHOT/versioned" \
    "$OPSHUB_TXN_SHARED_STAGE/downloads"
  opshub_txn_run install -d -m 0755 "$OPSHUB_TXN_SHARED_STAGE/web" "$OPSHUB_TXN_SHARED_STAGE/help"

  if opshub_txn_run test -e "$DOWNLOADS_DIR"; then
    opshub_txn_run test -d "$DOWNLOADS_DIR" && ! opshub_txn_run test -L "$DOWNLOADS_DIR" ||
      opshub_txn_die "downloads path is not a real directory"
    opshub_txn_run install -m 0600 /dev/null "$OPSHUB_TXN_SHARED_SNAPSHOT/DOWNLOADS_DIR_PRESENT"
  fi
  if opshub_txn_run test -e "$WEB_DIR"; then
    opshub_txn_run test -d "$WEB_DIR" && ! opshub_txn_run test -L "$WEB_DIR" ||
      opshub_txn_die "web path is not a real directory"
    opshub_txn_run cp -a --reflink=auto -- "$WEB_DIR" "$OPSHUB_TXN_SHARED_SNAPSHOT/web"
  fi
  if opshub_txn_run test -e "$DOWNLOADS_DIR/help"; then
    opshub_txn_run test -d "$DOWNLOADS_DIR/help" && ! opshub_txn_run test -L "$DOWNLOADS_DIR/help" ||
      opshub_txn_die "help path is not a real directory"
    opshub_txn_run cp -a --reflink=auto -- "$DOWNLOADS_DIR/help" "$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/help"
  fi
  local name live backup
  for name in latest.json download.html opshub-icon-192.png; do
    live="$DOWNLOADS_DIR/$name"
    backup="$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/$name"
    if opshub_txn_run test -e "$live"; then
      opshub_txn_run test -f "$live" && ! opshub_txn_run test -L "$live" ||
        opshub_txn_die "shared file has unexpected type: $live"
      opshub_txn_run cp -a --reflink=auto -- "$live" "$backup"
    fi
  done
  for name in "${APK_NAME:-}" "${WINDOWS_ZIP_NAME:-}" "${WINDOWS_INSTALLER_NAME:-}" "${WINDOWS_CHECKSUM_NAME:-}"; do
    [[ -n "$name" ]] || continue
    live="$DOWNLOADS_DIR/$name"
    backup="$OPSHUB_TXN_SHARED_SNAPSHOT/versioned/$name"
    if opshub_txn_run test -e "$live"; then
      opshub_txn_run test -f "$live" && ! opshub_txn_run test -L "$live" ||
        opshub_txn_die "versioned artifact has unexpected type: $live"
      opshub_txn_run cp -a --reflink=auto -- "$live" "$backup"
    fi
  done
  opshub_txn_run install -m 0600 /dev/null "$OPSHUB_TXN_SHARED_SNAPSHOT/SNAPSHOT_READY"
  opshub_txn_run install -m 0600 /dev/null "$OPSHUB_TXN_SHARED_SNAPSHOT/PROMOTION_STARTED"
}

opshub_txn_stage_shared() {
  : "${TXN_INPUT_DIR:?TXN_INPUT_DIR is required}"
  : "${TXN_CLIENT_DIR:?TXN_CLIENT_DIR is required}"
  opshub_txn_snapshot_shared
  opshub_txn_run tar --no-same-owner -xzf "$TXN_INPUT_DIR/web.tar.gz" -C "$OPSHUB_TXN_SHARED_STAGE/web"
  opshub_txn_run tar --no-same-owner -xzf "$TXN_INPUT_DIR/help-assets.tar.gz" -C "$OPSHUB_TXN_SHARED_STAGE/help"
  opshub_txn_run test -s "$OPSHUB_TXN_SHARED_STAGE/web/index.html" || opshub_txn_die "staged web bundle is incomplete"
  opshub_txn_run test -d "$OPSHUB_TXN_SHARED_STAGE/help/assets" || opshub_txn_die "staged help bundle is incomplete"
  local name staged
  for name in latest.json download.html opshub-icon-192.png; do
    opshub_txn_run install -m 0644 "$TXN_INPUT_DIR/$name" "$OPSHUB_TXN_SHARED_STAGE/downloads/$name"
  done
  for name in "${APK_NAME:-}" "${WINDOWS_ZIP_NAME:-}" "${WINDOWS_INSTALLER_NAME:-}" "${WINDOWS_CHECKSUM_NAME:-}"; do
    [[ -n "$name" ]] || continue
    staged="$TXN_CLIENT_DIR/$name"
    if ! opshub_txn_run test -s "$staged"; then
      for subdir in android windows; do
        if opshub_txn_run test -s "$TXN_CLIENT_DIR/$subdir/$name"; then
          staged="$TXN_CLIENT_DIR/$subdir/$name"
          break
        fi
      done
    fi
    opshub_txn_run test -s "$staged" || opshub_txn_die "staged client artifact is missing: $name"
    opshub_txn_run install -m 0644 "$staged" "$OPSHUB_TXN_SHARED_STAGE/downloads/$name"
  done
  if ! opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/DOWNLOADS_DIR_PRESENT"; then
    opshub_txn_run install -d -m 0755 "$DOWNLOADS_DIR"
  fi
  opshub_txn_run rm -rf -- "$WEB_DIR" "$DOWNLOADS_DIR/help"
  opshub_txn_run mv -T -- "$OPSHUB_TXN_SHARED_STAGE/web" "$WEB_DIR"
  opshub_txn_run mv -T -- "$OPSHUB_TXN_SHARED_STAGE/help" "$DOWNLOADS_DIR/help"
  for name in latest.json download.html opshub-icon-192.png "${APK_NAME:-}" "${WINDOWS_ZIP_NAME:-}" "${WINDOWS_INSTALLER_NAME:-}" "${WINDOWS_CHECKSUM_NAME:-}"; do
    [[ -n "$name" ]] || continue
    opshub_txn_run mv -Tf -- "$OPSHUB_TXN_SHARED_STAGE/downloads/$name" "$DOWNLOADS_DIR/$name"
  done
  opshub_txn_run install -m 0600 /dev/null "$OPSHUB_TXN_SHARED_SNAPSHOT/PROMOTED"
}

opshub_txn_snapshot_static_current() {
  : "${CURRENT_DIR:?CURRENT_DIR is required}"
  local static_snapshot="$OPSHUB_TXN_SHARED_SNAPSHOT/static"
  opshub_txn_run install -d -m 0700 "$static_snapshot"
  opshub_txn_run test -f "$CURRENT_DIR/deploy/home-server/Caddyfile" ||
    opshub_txn_die "current Caddyfile is unavailable"
  opshub_txn_run cp -a -- "$CURRENT_DIR/deploy/home-server/Caddyfile" "$static_snapshot/Caddyfile"
  if opshub_txn_run test -e "$CURRENT_DIR/docs/help"; then
    opshub_txn_run test -d "$CURRENT_DIR/docs/help" && ! opshub_txn_run test -L "$CURRENT_DIR/docs/help" ||
      opshub_txn_die "current runtime Help path is not a real directory"
    opshub_txn_run cp -a -- "$CURRENT_DIR/docs/help" "$static_snapshot/docs-help"
  fi
  opshub_txn_run install -m 0600 /dev/null "$static_snapshot/SNAPSHOT_READY"
}

opshub_txn_promote_static() {
  : "${TXN_INPUT_DIR:?TXN_INPUT_DIR is required}"
  opshub_txn_snapshot_shared
  opshub_txn_snapshot_static_current
  local static_stage="$OPSHUB_TXN_SHARED_STAGE/static"
  opshub_txn_run install -d -m 0755 "$static_stage/docs-help"
  opshub_txn_run tar --no-same-owner -xzf "$TXN_INPUT_DIR/docs-help.tar.gz" -C "$static_stage/docs-help"
  opshub_txn_run test -s "$TXN_INPUT_DIR/latest.json" || opshub_txn_die "staged static manifest is missing"
  opshub_txn_run test -s "$TXN_INPUT_DIR/download.html" || opshub_txn_die "staged download page is missing"
  opshub_txn_run test -s "$TXN_INPUT_DIR/opshub-icon-192.png" || opshub_txn_die "staged download icon is missing"
  opshub_txn_run test -s "$TXN_INPUT_DIR/Caddyfile" || opshub_txn_die "staged Caddyfile is missing"
  opshub_txn_run test -d "$static_stage/docs-help/assets" || opshub_txn_die "staged Help assets are missing"
  opshub_txn_run install -m 0644 "$TXN_INPUT_DIR/Caddyfile" "$CURRENT_DIR/deploy/home-server/Caddyfile"
  opshub_txn_run install -d -m 0755 "$CURRENT_DIR/docs" "$DOWNLOADS_DIR"
  opshub_txn_run install -m 0644 "$TXN_INPUT_DIR/latest.json" "$OPSHUB_TXN_SHARED_STAGE/downloads/latest.json"
  opshub_txn_run install -m 0644 "$TXN_INPUT_DIR/download.html" "$OPSHUB_TXN_SHARED_STAGE/downloads/download.html"
  opshub_txn_run install -m 0644 "$TXN_INPUT_DIR/opshub-icon-192.png" "$OPSHUB_TXN_SHARED_STAGE/downloads/opshub-icon-192.png"
  opshub_txn_run rm -rf -- "$DOWNLOADS_DIR/help"
  opshub_txn_run rm -rf -- "$CURRENT_DIR/docs/help"
  opshub_txn_run cp -a -- "$static_stage/docs-help" "$CURRENT_DIR/docs/help"
  opshub_txn_run install -d -m 0755 "$DOWNLOADS_DIR/help"
  opshub_txn_run cp -a -- "$static_stage/docs-help/assets/." "$DOWNLOADS_DIR/help/assets"
  local name
  for name in latest.json download.html opshub-icon-192.png; do
    opshub_txn_run mv -Tf -- "$OPSHUB_TXN_SHARED_STAGE/downloads/$name" "$DOWNLOADS_DIR/$name"
  done
  opshub_txn_run install -m 0600 /dev/null "$OPSHUB_TXN_SHARED_SNAPSHOT/PROMOTED"
}

opshub_txn_restore_static_current() {
  local static_snapshot="$OPSHUB_TXN_SHARED_SNAPSHOT/static"
  opshub_txn_run test -e "$static_snapshot/SNAPSHOT_READY" || { opshub_txn_die "static snapshot is incomplete"; return 1; }
  opshub_txn_run cp -a -- "$static_snapshot/Caddyfile" "$CURRENT_DIR/deploy/home-server/Caddyfile" || return 1
  opshub_txn_run rm -rf -- "$CURRENT_DIR/docs/help" || return 1
  if opshub_txn_run test -e "$static_snapshot/docs-help"; then
    opshub_txn_run cp -a -- "$static_snapshot/docs-help" "$CURRENT_DIR/docs/help" || return 1
  fi
  opshub_txn_run test -f "$CURRENT_DIR/deploy/home-server/Caddyfile" || return 1
  if opshub_txn_run test -e "$static_snapshot/docs-help"; then
    opshub_txn_run test -d "$CURRENT_DIR/docs/help/assets" || return 1
  fi
}

opshub_txn_restore_shared() {
  : "${DOWNLOADS_DIR:?DOWNLOADS_DIR is required}"
  : "${WEB_DIR:?WEB_DIR is required}"
  opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/SNAPSHOT_READY" || {
    opshub_txn_die "shared snapshot is incomplete"
    return 1
  }
  opshub_txn_run rm -rf -- "$WEB_DIR" "$DOWNLOADS_DIR/help" || return 1
  if opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/web"; then
    opshub_txn_run cp -a --reflink=auto -- "$OPSHUB_TXN_SHARED_SNAPSHOT/web" "$WEB_DIR" || return 1
  fi
  if opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/help"; then
    opshub_txn_run cp -a --reflink=auto -- "$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/help" "$DOWNLOADS_DIR/help" || return 1
  fi
  local name live backup
  for name in latest.json download.html opshub-icon-192.png; do
    live="$DOWNLOADS_DIR/$name"; backup="$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/$name"
    opshub_txn_run rm -f -- "$live" || return 1
    if opshub_txn_run test -e "$backup"; then opshub_txn_run cp -a --reflink=auto -- "$backup" "$live" || return 1; fi
  done
  for name in "${APK_NAME:-}" "${WINDOWS_ZIP_NAME:-}" "${WINDOWS_INSTALLER_NAME:-}" "${WINDOWS_CHECKSUM_NAME:-}"; do
    [[ -n "$name" ]] || continue
    live="$DOWNLOADS_DIR/$name"; backup="$OPSHUB_TXN_SHARED_SNAPSHOT/versioned/$name"
    opshub_txn_run rm -f -- "$live" || return 1
    if opshub_txn_run test -e "$backup"; then opshub_txn_run cp -a --reflink=auto -- "$backup" "$live" || return 1; fi
  done
  if ! opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/DOWNLOADS_DIR_PRESENT"; then
    opshub_txn_run rmdir -- "$DOWNLOADS_DIR" || return 1
  fi
  opshub_txn_run test -d "$WEB_DIR" || return 1
  if opshub_txn_run test -e "$OPSHUB_TXN_SHARED_SNAPSHOT/downloads/help"; then
    opshub_txn_run test -d "$DOWNLOADS_DIR/help" || return 1
  fi
}

opshub_txn_restore_env() {
  if ! opshub_txn_run test -s "$OPSHUB_TXN_ENV_SNAPSHOT"; then
    opshub_txn_die "env snapshot is unavailable"
    return 1
  fi
  local restore_tmp="${OPSHUB_ENV_FILE}.restore.${OPSHUB_TXN_ID}"
  opshub_txn_run cp --preserve=mode,ownership,timestamps -- "$OPSHUB_TXN_ENV_SNAPSHOT" "$restore_tmp" || return 1
  opshub_txn_run mv -Tf -- "$restore_tmp" "$OPSHUB_ENV_FILE" || return 1
}

opshub_txn_previous_release() {
  opshub_txn_run sed -n '1p' "$OPSHUB_TXN_STATE"
}

opshub_txn_candidate_release() {
  opshub_txn_run sed -n '2p' "$OPSHUB_TXN_STATE"
}

opshub_txn_cleanup() {
  opshub_txn_run rm -f -- "$OPSHUB_TXN_STATE_TMP" "$OPSHUB_TXN_STATE" "$OPSHUB_TXN_ENV_SNAPSHOT"
  opshub_txn_run rm -rf -- "$OPSHUB_TXN_SHARED_STAGE" "$OPSHUB_TXN_SHARED_SNAPSHOT"
}
