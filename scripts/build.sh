#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
configuration="${1:-release}"

case "$configuration" in
    debug|release) ;;
    *) printf 'Usage: %s [debug|release]\n' "$0" >&2; exit 2 ;;
esac

swift build --package-path "$root" --configuration "$configuration" >&2
bin_dir="$(swift build --package-path "$root" --configuration "$configuration" --show-bin-path)"
printf '%s/WeAlfred\n' "$bin_dir"
