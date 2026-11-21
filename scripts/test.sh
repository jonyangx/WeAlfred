#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
options=(--disable-xctest)
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ "$developer_dir" == */CommandLineTools ]]; then
    macros="$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
    if [[ -f "$macros" ]]; then
        # Swift Build in Command Line Tools may not discover the Testing macro library.
        options+=(-Xswiftc -load-plugin-library -Xswiftc "$macros")
    fi
fi
swift test --package-path "$root" "${options[@]}"

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/wealfred-test.XXXXXX")"
trap 'rm -rf -- "$temp_dir"' EXIT
WEALFRED_OUTPUT_DIR="$temp_dir/output" "$root/scripts/package.sh"

app="$temp_dir/output/WeAlfred.app"
plist="$app/Contents/Info.plist"
executable="$(plutil -extract CFBundleExecutable raw "$plist")"
test -x "$app/Contents/MacOS/$executable"
test "$(plutil -extract LSUIElement raw "$plist")" = true
test -f "$app/Contents/Resources/WeAlfred.icns"
test "$(plutil -extract CFBundleIconFile raw "$plist")" = "WeAlfred"
codesign --verify --strict "$app"

unzip -tq "$temp_dir/output/WeAlfred.zip"
ditto -x -k "$temp_dir/output/WeAlfred.zip" "$temp_dir/extracted"
codesign --verify --strict "$temp_dir/extracted/WeAlfred.app"
printf 'Bundle and ZIP checks passed.\n'
