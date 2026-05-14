#!/bin/zsh
# Render an emoji glyph (e.g. 💾) into a macOS .icns file.
# Apple Color Emoji is a bitmap font; Pillow can't rasterize it and the
# system python3 has no AppKit, so we delegate rendering to a small Swift
# program that uses AppKit's NSAttributedString.draw.
#
# Usage: emoji-to-icns.sh <emoji> <output.icns>
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <emoji> <output.icns>" >&2
  exit 2
fi
emoji="$1"
out="$2"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/render.swift" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { fputs("render <emoji> <out.png>\n", stderr); exit(2) }
let emoji = args[1]
let outPath = args[2]

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

NSColor.clear.set()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let font = NSFont(name: "Apple Color Emoji", size: size * 0.8)!
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let s = emoji as NSString
let bbox = s.size(withAttributes: attrs)
let x = (size - bbox.width) / 2
let y = (size - bbox.height) / 2
s.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr); exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath))
SWIFT

/usr/bin/swift "$tmp/render.swift" "$emoji" "$tmp/icon_1024.png"

set_dir="$tmp/icon.iconset"
mkdir "$set_dir"
for s in 16 32 128 256 512; do
  /usr/bin/sips -z $s $s "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
  /usr/bin/sips -z $((s*2)) $((s*2)) "$tmp/icon_1024.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
done
cp "$tmp/icon_1024.png" "$set_dir/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$set_dir" -o "$out"
echo "wrote $out"
