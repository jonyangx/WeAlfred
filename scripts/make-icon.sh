#!/usr/bin/env bash
# 绘制应用图标（青绿渐变底 + 白色 ⌘ 符号）并生成 Resources/WeAlfred.icns。
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/wealfred-icon.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
iconset="$work/WeAlfred.iconset"
mkdir "$iconset"

cat > "$work/draw.swift" <<'EOF'
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225).addClip()
NSGradient(starting: NSColor(calibratedRed: 0.06, green: 0.62, blue: 0.53, alpha: 1),
           ending: NSColor(calibratedRed: 0.0, green: 0.44, blue: 0.37, alpha: 1))?
    .draw(in: rect, angle: -90)

let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: "WeAlfred")!
let glyph = symbol
    .withSymbolConfiguration(.init(pointSize: 600, weight: .medium))!
    .withSymbolConfiguration(.init(paletteColors: [.white]))!
let scale = size * 0.56 / max(glyph.size.width, glyph.size.height)
let width = glyph.size.width * scale, height = glyph.size.height * scale
glyph.draw(
    in: NSRect(x: (size - width) / 2, y: (size - height) / 2, width: width, height: height),
    from: .zero, operation: .sourceOver, fraction: 1
)
image.unlockFocus()

let png = NSBitmapImageRep(data: image.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
try! png.write(to: output)
EOF

swift "$work/draw.swift" "$work/icon.png"

# iconutil 要求 iconset 目录内使用固定的命名和尺寸组合。
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
    128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x \
    512:icon_512x512 1024:icon_512x512@2x; do
    pixels="${spec%%:*}"; name="${spec##*:}"
    sips -z "$pixels" "$pixels" --out "$iconset/$name.png" "$work/icon.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$root/Resources/WeAlfred.icns"
printf '%s\n' "$root/Resources/WeAlfred.icns"
