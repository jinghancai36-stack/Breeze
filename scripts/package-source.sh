#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
artifacts_dir="$project_dir/artifacts"

cd "$project_dir"
if [ -n "$(git status --porcelain)" ]; then
  printf 'Error: source packaging requires a clean worktree.\n' >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Config/Breeze-Info.plist")
archive="$artifacts_dir/Breeze-$version-source.zip"
checksum="$archive.sha256"

mkdir -p "$artifacts_dir"
git archive --format=zip --prefix="Breeze-$version/" --output="$archive" HEAD
(
  cd "$artifacts_dir"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

printf 'Source archive: %s\n' "$archive"
printf 'Checksum: %s\n' "$checksum"
