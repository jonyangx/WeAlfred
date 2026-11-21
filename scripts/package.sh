#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
output="${WEALFRED_OUTPUT_DIR:-$root/dist}"
identity="${WEALFRED_SIGN_IDENTITY:--}"
binary="$("$root/scripts/build.sh" release)"

mkdir -p "$output"
stage="$(mktemp -d "$output/.wealfred-package.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT

app="$stage/WeAlfred.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
install -m 755 "$binary" "$app/Contents/MacOS/WeAlfred"
install -m 644 "$root/Resources/Info.plist" "$app/Contents/Info.plist"
install -m 644 "$root/Resources/WeAlfred.icns" "$app/Contents/Resources/WeAlfred.icns"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign "$identity" --timestamp=none "$app"
codesign --verify --strict "$app"
ditto -c -k --keepParent "$app" "$stage/WeAlfred.zip"

# A directory must be moved away before the new bundle can take its place.
if [[ -e "$output/WeAlfred.app" || -L "$output/WeAlfred.app" ]]; then
    mv "$output/WeAlfred.app" "$stage/previous.app"
fi
if ! mv "$app" "$output/WeAlfred.app"; then
    if [[ -e "$stage/previous.app" || -L "$stage/previous.app" ]]; then
        mv "$stage/previous.app" "$output/WeAlfred.app"
    fi
    exit 1
fi
mv -f "$stage/WeAlfred.zip" "$output/WeAlfred.zip"
printf '%s\n' "$output/WeAlfred.app" "$output/WeAlfred.zip"
