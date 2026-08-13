#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}

DEVELOPER_DIR="$developer_dir" xcodebuild \
  -project "$project_dir/Breeze.xcodeproj" \
  -scheme Breeze \
  -configuration Release \
  -derivedDataPath "$project_dir/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$project_dir/dist" \
  CODE_SIGNING_ALLOWED=NO \
  build

app="$project_dir/dist/Breeze.app"
helper="$app/Contents/MacOS/BreezeHelper"
# A rebuilt local artifact can inherit stale Gatekeeper provenance from a prior
# launch. Clear metadata only from this generated bundle before signing it.
xattr -cr "$app"
signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development:/ {print $2; exit}')

if [ -n "$signing_identity" ]; then
  codesign --force --sign "$signing_identity" --options runtime \
    --identifier com.cai.Breeze.Helper "$helper"
  codesign --force --sign "$signing_identity" --options runtime \
    --identifier com.cai.Breeze "$app"
  printf 'Signed with an Apple Development identity for local Helper testing.\n'
else
  codesign --force --sign - --options runtime --identifier com.cai.Breeze.Helper "$helper"
  codesign --force --sign - --options runtime --identifier com.cai.Breeze "$app"
  printf 'Warning: no Apple Development identity was found; the root Helper cannot launch with an ad-hoc signature.\n' >&2
fi

printf '\nBuilt app: %s\n' "$project_dir/dist/Breeze.app"
