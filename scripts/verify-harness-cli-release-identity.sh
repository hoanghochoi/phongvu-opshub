#!/usr/bin/env bash
set -euo pipefail

[[ $# == 4 ]] || {
  echo "usage: $0 <pretag|tagged> <harness-cli-vX.Y.Z> <source-sha> <proof-run-id>" >&2
  exit 2
}

mode=$1
tag=$2
source_sha=$3
proof_run=$4

case "$mode" in
  pretag|tagged) ;;
  *)
    echo "release identity rejected: mode must be pretag or tagged" >&2
    exit 2
    ;;
esac
[[ "$tag" =~ ^harness-cli-v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || {
  echo "release identity rejected: invalid stable tag: $tag" >&2
  exit 1
}
expected_version=${BASH_REMATCH[1]}
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || {
  echo "release identity rejected: source SHA must be 40 lowercase hex characters" >&2
  exit 1
}
[[ "$proof_run" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "release identity rejected: proof run id contains unsupported characters" >&2
  exit 1
}

head_sha=$(git rev-parse HEAD)
[[ "$head_sha" == "$source_sha" ]] || {
  echo "release identity rejected: HEAD $head_sha does not match source $source_sha" >&2
  exit 1
}
git rev-parse --verify --quiet "$source_sha^{commit}" >/dev/null || {
  echo "release identity rejected: source commit is unavailable: $source_sha" >&2
  exit 1
}
git show-ref --verify --quiet refs/remotes/origin/main || {
  echo "release identity rejected: origin/main is unavailable" >&2
  exit 1
}
git merge-base --is-ancestor "$source_sha" refs/remotes/origin/main || {
  echo "release identity rejected: source $source_sha is not reachable from origin/main" >&2
  exit 1
}

crate_version=$(awk -F'"' '/^version = / {print $2; exit}' crates/harness-cli/Cargo.toml)
[[ "$crate_version" == "$expected_version" ]] || {
  echo "release identity rejected: tag version $expected_version does not match crate version $crate_version" >&2
  exit 1
}
lock_version=$(awk '
  /^name = "harness-cli"$/ { package = 1; next }
  package && /^version = / { gsub(/"/, "", $3); print $3; exit }
' Cargo.lock)
[[ "$lock_version" == "$expected_version" ]] || {
  echo "release identity rejected: tag version $expected_version does not match Cargo.lock version $lock_version" >&2
  exit 1
}
release_pin=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' scripts/harness-cli-release-tag)
[[ "$release_pin" == "$tag" ]] || {
  echo "release identity rejected: release pin $release_pin does not match requested tag $tag" >&2
  exit 1
}

remote_oid=$(git ls-remote --refs origin "refs/tags/$tag" | awk 'NR == 1 {print $1}')
if [[ -z "$remote_oid" ]]; then
  [[ "$mode" == pretag ]] || {
    echo "release identity rejected: remote tag is absent: $tag" >&2
    exit 1
  }
  if git show-ref --verify --quiet "refs/tags/$tag"; then
    echo "release identity rejected: local tag exists while remote tag is absent: $tag" >&2
    exit 1
  fi
  echo "release candidate identity passed: tag=$tag source_commit=$source_sha crate_version=$crate_version proof_run=$proof_run tag_state=absent"
  exit 0
fi

git fetch --force --quiet origin "refs/tags/$tag:refs/tags/$tag"
tag_type=$(git cat-file -t "refs/tags/$tag")
[[ "$tag_type" == tag ]] || {
  echo "release identity rejected: release tag must be annotated: $tag" >&2
  exit 1
}
tag_sha=$(git rev-parse "refs/tags/$tag^{commit}")
[[ "$tag_sha" == "$source_sha" ]] || {
  echo "release identity rejected: tag $tag resolves to $tag_sha, expected $source_sha" >&2
  exit 1
}
annotation=$(git for-each-ref --format='%(contents)' "refs/tags/$tag")
marker="proof-run=$proof_run source=$source_sha"
grep -Fxq "$marker" <<<"$annotation" || {
  echo "release identity rejected: tag $tag is not owned by proof run $proof_run" >&2
  exit 1
}

echo "release $mode identity passed: tag=$tag source_commit=$source_sha crate_version=$crate_version proof_run=$proof_run tag_state=present"
