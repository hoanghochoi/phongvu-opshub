#!/usr/bin/env bash
set -euo pipefail
umask 077

BACKUP_DIR="${1:?Usage: verify-bidv-backup.sh BACKUP_DIR AGE_IDENTITY_FILE}"
AGE_IDENTITY_FILE="${2:?Usage: verify-bidv-backup.sh BACKUP_DIR AGE_IDENTITY_FILE}"

[[ -d "$BACKUP_DIR" && -f "$BACKUP_DIR/.opshub-backup" ]] || {
  echo "Not an OpsHub backup directory." >&2
  exit 1
}
[[ -f "$AGE_IDENTITY_FILE" ]] || { echo "Missing age identity file." >&2; exit 1; }

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

manifest="$BACKUP_DIR/manifest.txt"
grep -qx 'encryption=age' "$manifest" || {
  echo "BIDV restore proof requires age encryption." >&2
  exit 1
}
postgres_archive="$(sed -n 's/^postgres_dump=//p' "$manifest")"
kek_archive="$(sed -n 's/^bidv_kek_archive=//p' "$manifest")"
[[ "$postgres_archive" == *.age && "$kek_archive" == *.age ]] || {
  echo "Database and BIDV KEK must both be age-encrypted." >&2
  exit 1
}

age --decrypt --identity "$AGE_IDENTITY_FILE" "$BACKUP_DIR/$postgres_archive" |
  gzip -t
age --decrypt --identity "$AGE_IDENTITY_FILE" "$BACKUP_DIR/$kek_archive" |
  tar -tzf - | grep -qx 'bidv-h2h-kek'

echo "BIDV backup checksum/decryption structure PASS"
