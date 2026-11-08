#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2015 - 2026 Rime community
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Create the changelog commit for a release and tag it.
#
# "make cliff" renders the newest changelog section from the tag on HEAD, so
# the tag is created before the changelog is generated and moved onto the
# changelog commit afterwards. The changelog is regenerated once more so that
# it also contains its own release commit.
#
# Usage: script/tag.sh [VERSION] [--push]
#
# VERSION defaults to versionName in app/build.gradle.kts.

set -euo pipefail

GRADLE_FILE="app/build.gradle.kts"
CHANGELOG="CHANGELOG.md"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }
step() { printf '\n==> %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: script/tag.sh [VERSION] [--push]

Create the changelog commit for a release and tag it.

VERSION is X.Y.Z or vX.Y.Z; it defaults to versionName from
app/build.gradle.kts.

  --push          Push the branch and tag after tagging.
  -h, --help      Show this help.
EOF
}

version_arg=""
push=0

while (($# > 0)); do
	case $1 in
	-h | --help) usage; exit 0 ;;
	--push) push=1 ;;
	-*) die "unknown option: $1 (try --help)" ;;
	*)
		[[ -z $version_arg ]] || die "unexpected argument: $1"
		version_arg=$1
		;;
	esac
	shift
done

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"

branch=$(git symbolic-ref --short -q HEAD) || die "HEAD is detached"
[[ -f $GRADLE_FILE ]] || die "missing $GRADLE_FILE"

version_name=$(sed -n 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$GRADLE_FILE")
[[ -n $version_name ]] || die "cannot read versionName from $GRADLE_FILE"

version=${version_arg:-$version_name}
version=${version#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: $version (expected X.Y.Z)"
[[ -z $version_arg || $version == "$version_name" ]] ||
	warn "using $version, but versionName is $version_name"
tag="v$version"

git show-ref --verify --quiet "refs/tags/$tag" && die "tag $tag already exists"
[[ -z $(git status --porcelain --untracked-files=no --ignore-submodules=all) ]] ||
	die "working tree is not clean"
command -v git-cliff >/dev/null 2>&1 || die "git-cliff is not installed"
command -v make >/dev/null 2>&1 || die "make is not installed"

printf '    version: %s\n    branch:  %s\n' "$tag" "$branch"

step "Generating the $tag changelog"
git tag -a "$tag" -m "$tag"
make cliff

step "Committing the changelog"
git commit -m "chore: add $version changelog" -- "$CHANGELOG"

step "Finalizing $tag"
git tag -f -a "$tag" -m "$tag"
make cliff
git commit --amend --no-edit -- "$CHANGELOG"
git tag -f -a "$tag" -m "$tag"

step "Verifying the changelog is stable"
make cliff
git diff --exit-code -- "$CHANGELOG" ||
	die "$CHANGELOG changed after tagging; refusing to finish"

if ((push)); then
	git push origin "$branch" "$tag"
else
	printf '\nCreated %s. Push it with:\n  git push origin %s %s\n' "$tag" "$branch" "$tag"
fi
