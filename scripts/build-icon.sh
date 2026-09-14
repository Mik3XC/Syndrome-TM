#!/bin/zsh
# Copyright 2026 Premise LLC
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/icon
xcrun swiftc -parse-as-library Sources/Syndrome/Brand.swift scripts/RenderIcon.swift -o .build/icon/render
.build/icon/render "$PWD/output.png"
icon_dir="$PWD/.build/icon/Syndrome.iconset"
mkdir -p "$icon_dir"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" output.png --out "$icon_dir/icon_${size}x${size}.png" >/dev/null
    twice=$((size * 2))
    /usr/bin/sips -z "$twice" "$twice" output.png --out "$icon_dir/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$icon_dir" -o Resources/Syndrome.icns
print "Rendered SwiftUI alien logo to output.png and Resources/Syndrome.icns"
