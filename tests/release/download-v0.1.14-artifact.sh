#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] || {
  echo "usage: $0 <asset-name> <output-path>" >&2
  exit 2
}

asset=$1
output=$2
tag=harness-cli-v0.1.14

case "$asset" in
  harness-cli-macos-arm64)
    expected=0adcd5360cd636c189fe0cd958e5b73261f7012a4e43631f08c61269c785caf9
    ;;
  harness-cli-macos-x64)
    expected=d0ee0b6b9f702eb87824e96b42d7a8382012b542a076e8ce2d0b1bb8d6201168
    ;;
  harness-cli-linux-x64)
    expected=d2551d32490d0af78f8eb387d8854771ebfcde2260b068539384592668cc54a6
    ;;
  harness-cli-linux-arm64)
    expected=8828d624075fbae2f44b6f57ac651bdacb2e7c60ed0cc15853b9481b3edf0161
    ;;
  harness-cli-windows-x64.exe)
    expected=abd5a4176d52b3576c66932f44f377d2667fba409011de145044f425fd0a82ca
    ;;
  *)
    echo "unsupported v0.1.14 release asset: $asset" >&2
    exit 2
    ;;
esac

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "shasum or sha256sum is required" >&2
    exit 1
  fi
}

mkdir -p "$(dirname "$output")"
sidecar=$(mktemp)
trap 'rm -f "$sidecar"' EXIT
base="https://github.com/hoangnb24/repository-harness/releases/download/$tag"
curl -fsSL "$base/$asset" -o "$output"
curl -fsSL "$base/$asset.sha256" -o "$sidecar"

published=$(awk '{print $1; exit}' "$sidecar")
[[ "$published" == "$expected" ]] || {
  echo "published checksum for $asset drifted: expected $expected, got $published" >&2
  exit 1
}
actual=$(sha256_file "$output")
[[ "$actual" == "$expected" ]] || {
  echo "downloaded checksum for $asset differs: expected $expected, got $actual" >&2
  exit 1
}

case "$asset" in
  *.exe) ;;
  *) chmod 755 "$output" ;;
esac

echo "verified pinned $tag artifact: asset=$asset sha256=$actual"
