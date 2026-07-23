#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
repo="$temp/repo"
remote="$temp/remote.git"

mkdir -p "$repo/crates/harness-cli" "$repo/scripts"
cp "$root/scripts/verify-harness-cli-release-identity.sh" "$repo/scripts/"
cp "$root/scripts/promote-harness-cli-release-tag.sh" "$repo/scripts/"
chmod +x "$repo/scripts/"*.sh
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
git -C "$repo" config user.name "release promotion test"
git -C "$repo" config user.email "release-promotion@example.invalid"
git -C "$repo" add .
git -C "$repo" commit -q -m initial
git init -q --bare "$remote"
git -C "$repo" remote add origin "$remote"
git -C "$repo" push -q -u origin main
source_sha=$(git -C "$repo" rev-parse HEAD)

(cd "$repo" && scripts/promote-harness-cli-release-tag.sh \
  harness-cli-v1.2.3 "$source_sha" run-123) >/dev/null
first_tag=$(git -C "$repo" ls-remote --refs origin refs/tags/harness-cli-v1.2.3 | awk '{print $1}')
first_commit=$(git -C "$repo" ls-remote origin 'refs/tags/harness-cli-v1.2.3^{}' | awk '{print $1}')
[[ -n "$first_tag" && "$first_commit" == "$source_sha" ]]

# A retry from the same proof run is idempotent.
(cd "$repo" && scripts/promote-harness-cli-release-tag.sh \
  harness-cli-v1.2.3 "$source_sha" run-123) >/dev/null
[[ "$(git -C "$repo" ls-remote --refs origin refs/tags/harness-cli-v1.2.3 | awk '{print $1}')" == "$first_tag" ]]

# A different proof run cannot claim or move the existing tag.
if (cd "$repo" && scripts/promote-harness-cli-release-tag.sh \
  harness-cli-v1.2.3 "$source_sha" run-456) >"$temp/other-run.out" 2>&1; then
  echo "different proof run unexpectedly reused release tag" >&2
  exit 1
fi
[[ "$(git -C "$repo" ls-remote --refs origin refs/tags/harness-cli-v1.2.3 | awk '{print $1}')" == "$first_tag" ]]

git -C "$repo" commit --allow-empty -q -m later
later_sha=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" push -q origin main
if (cd "$repo" && scripts/promote-harness-cli-release-tag.sh \
  harness-cli-v1.2.3 "$later_sha" run-789) >"$temp/other-source.out" 2>&1; then
  echo "different source unexpectedly moved release tag" >&2
  exit 1
fi
[[ "$(git -C "$repo" ls-remote --refs origin refs/tags/harness-cli-v1.2.3 | awk '{print $1}')" == "$first_tag" ]]
[[ "$(git -C "$repo" ls-remote origin 'refs/tags/harness-cli-v1.2.3^{}' | awk '{print $1}')" == "$source_sha" ]]

echo "release promotion first-writer, same-run retry, and immutable collision guards passed"
