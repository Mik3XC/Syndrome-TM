#!/bin/zsh
# Copyright 2026 Premise LLC
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --product Syndrome
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/Syndrome.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Syndrome" "$app_dir/Contents/MacOS/Syndrome"
cp Resources/Syndrome.icns "$app_dir/Contents/Resources/Syndrome.icns"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp LICENSE NOTICE "$app_dir/Contents/Resources/"
/usr/bin/codesign --force --sign - "$app_dir"
print "Built: $app_dir"
