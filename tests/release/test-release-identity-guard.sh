#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
repo="$temp/repo"
remote="$temp/remote.git"

mkdir -p "$repo/crates/harness-cli" "$repo/scripts"
cp "$root/scripts/verify-harness-cli-release-identity.sh" "$repo/scripts/verify.sh"
chmod +x "$repo/scripts/verify.sh"
cat >"$repo/crates/harness-cli/Cargo.toml" <<'EOF'
[package]
name = "harness-cli"
version = "1.2.3"
EOF
cat >"$repo/Cargo.lock" <<'EOF'
version = 4

[[package]]
name = "harness-cli"
version = "1.2.3"
EOF
printf 'harness-cli-v1.2.3\n' >"$repo/scripts/harness-cli-release-tag"

git -C "$repo" init -q -b main
git -C "$repo" config user.name "release identity test"
git -C "$repo" config user.email "release-identity@example.invalid"
git -C "$repo" add .
git -C "$repo" commit -q -m initial
git init -q --bare "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin main
source_sha=$(git -C "$repo" rev-parse HEAD)

(cd "$repo" && scripts/verify.sh pretag harness-cli-v1.2.3 "$source_sha" run-123) >/dev/null

expect_failure() {
  local label=$1
  shift
  if (cd "$repo" && scripts/verify.sh "$@") >"$temp/failure.out" 2>&1; then
    echo "$label unexpectedly passed release identity" >&2
    exit 1
  fi
}

expect_failure "absent tagged identity" tagged harness-cli-v1.2.3 "$source_sha" run-123
expect_failure "invalid stable tag" pretag harness-cli-v1.2.3-rc1 "$source_sha" run-123
expect_failure "abbreviated source" pretag harness-cli-v1.2.3 "${source_sha:0:12}" run-123

sed -i.bak 's/version = "1.2.3"/version = "1.2.4"/' "$repo/crates/harness-cli/Cargo.toml"
rm "$repo/crates/harness-cli/Cargo.toml.bak"
expect_failure "crate version mismatch" pretag harness-cli-v1.2.3 "$source_sha" run-123
sed -i.bak 's/version = "1.2.4"/version = "1.2.3"/' "$repo/crates/harness-cli/Cargo.toml"
rm "$repo/crates/harness-cli/Cargo.toml.bak"

sed -i.bak 's/version = "1.2.3"/version = "9.9.9"/' "$repo/Cargo.lock"
rm "$repo/Cargo.lock.bak"
expect_failure "lockfile version mismatch" pretag harness-cli-v1.2.3 "$source_sha" run-123
sed -i.bak 's/version = "9.9.9"/version = "1.2.3"/' "$repo/Cargo.lock"
rm "$repo/Cargo.lock.bak"

printf 'harness-cli-v9.9.9\n' >"$repo/scripts/harness-cli-release-tag"
expect_failure "release pin mismatch" pretag harness-cli-v1.2.3 "$source_sha" run-123
printf 'harness-cli-v1.2.3\n' >"$repo/scripts/harness-cli-release-tag"

git -C "$repo" tag -a harness-cli-v1.2.3 "$source_sha" \
  -m "Harness CLI harness-cli-v1.2.3" \
  -m "proof-run=run-123 source=$source_sha"
git -C "$repo" push -q origin refs/tags/harness-cli-v1.2.3
(cd "$repo" && scripts/verify.sh pretag harness-cli-v1.2.3 "$source_sha" run-123) >/dev/null
(cd "$repo" && scripts/verify.sh tagged harness-cli-v1.2.3 "$source_sha" run-123) >/dev/null
expect_failure "different proof-run ownership" tagged harness-cli-v1.2.3 "$source_sha" run-456

git -C "$repo" push -q origin :refs/tags/harness-cli-v1.2.3
git -C "$repo" tag -d harness-cli-v1.2.3 >/dev/null
git -C "$repo" tag harness-cli-v1.2.3 "$source_sha"
git -C "$repo" push -q origin refs/tags/harness-cli-v1.2.3
expect_failure "lightweight release tag" tagged harness-cli-v1.2.3 "$source_sha" run-123

git -C "$repo" push -q origin :refs/tags/harness-cli-v1.2.3
git -C "$repo" tag -d harness-cli-v1.2.3 >/dev/null
git -C "$repo" commit --allow-empty -q -m later
later_sha=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" push -q origin main
git -C "$repo" tag -a harness-cli-v1.2.3 "$later_sha" \
  -m "Harness CLI harness-cli-v1.2.3" \
  -m "proof-run=run-123 source=$later_sha"
git -C "$repo" push -q origin refs/tags/harness-cli-v1.2.3
git -C "$repo" checkout -q --detach "$source_sha"
expect_failure "tag target mismatch" tagged harness-cli-v1.2.3 "$source_sha" run-123

echo "release pretag/tagged source, version, pin, annotation, and immutable-target identity negatives passed"
