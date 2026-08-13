#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
developer_dir=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
build_root="$project_dir/build/ReleaseCheck"
products_dir="$build_root/Products"
app="$products_dir/Breeze.app"

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'Error: Breeze release checks require macOS.\n' >&2
  exit 1
fi
if [ ! -x "$developer_dir/usr/bin/xcodebuild" ]; then
  printf 'Error: full Xcode toolchain not found at %s\n' "$developer_dir" >&2
  exit 1
fi

cd "$project_dir"

if [ "${BREEZE_ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  printf 'Error: release checks require a clean worktree. Use BREEZE_ALLOW_DIRTY=1 only while developing the check itself.\n' >&2
  exit 1
fi

printf '[1/8] Repository audit\n'
"$project_dir/scripts/repository-audit.sh"

printf '[2/8] Source and property-list validation\n'
git diff --check
plutil -lint "$project_dir/Config/Breeze-Info.plist" "$project_dir/Config/com.cai.Breeze.Helper.plist"

printf '[3/8] Debug tests\n'
DEVELOPER_DIR="$developer_dir" swift test

printf '[4/8] Optimized Release tests\n'
DEVELOPER_DIR="$developer_dir" swift test -c release

printf '[5/8] Xcode Release static analysis\n'
DEVELOPER_DIR="$developer_dir" "$developer_dir/usr/bin/xcodebuild" \
  -project "$project_dir/Breeze.xcodeproj" \
  -scheme Breeze \
  -configuration Release \
  -derivedDataPath "$build_root/Analyze" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

printf '[6/8] Isolated Release app build\n'
DEVELOPER_DIR="$developer_dir" "$developer_dir/usr/bin/xcodebuild" \
  -project "$project_dir/Breeze.xcodeproj" \
  -scheme Breeze \
  -configuration Release \
  -derivedDataPath "$build_root/Build" \
  CONFIGURATION_BUILD_DIR="$products_dir" \
  CODE_SIGNING_ALLOWED=NO \
  build

printf '[7/8] Version, architecture, and local signing checks\n'
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
helper_version=$(sed -n 's/.*helperVersion = "\([^"]*\)".*/\1/p' "$project_dir/Sources/BreezeIPC/BreezeHelperProtocol.swift")
if [ "$app_version" != "$helper_version" ]; then
  printf 'Error: app version %s does not match Helper protocol version %s.\n' "$app_version" "$helper_version" >&2
  exit 1
fi
if ! lipo -archs "$app/Contents/MacOS/Breeze" | tr ' ' '\n' | grep -qx arm64; then
  printf 'Error: Release app does not contain arm64.\n' >&2
  exit 1
fi

xattr -cr "$app"
signing_identity=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development:/ {print $2; exit}')
if [ -n "$signing_identity" ]; then
  codesign --force --sign "$signing_identity" --options runtime \
    --identifier com.cai.Breeze.Helper "$app/Contents/MacOS/BreezeHelper"
  codesign --force --sign "$signing_identity" --options runtime \
    --identifier com.cai.Breeze "$app"
  signature_kind='Apple Development (local testing only)'
else
  codesign --force --sign - --options runtime \
    --identifier com.cai.Breeze.Helper "$app/Contents/MacOS/BreezeHelper"
  codesign --force --sign - --options runtime \
    --identifier com.cai.Breeze "$app"
  signature_kind='ad-hoc (Monitor Only; privileged Helper unavailable)'
fi
codesign --verify --deep --strict --verbose=2 "$app"

printf '[8/8] Release summary\n'
printf 'Breeze %s (%s)\n' "$app_version" "$build_number"
printf 'Signature: %s\n' "$signature_kind"
printf 'Validated app: %s\n' "$app"
printf 'Release checks passed. This does not replace Developer ID signing, notarization, or clean-Mac testing.\n'
