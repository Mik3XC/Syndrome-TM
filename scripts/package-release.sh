#!/bin/zsh
# Copyright 2026 Premise LLC
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "${0:A:h:h}"

# Command Line Tools suffice: build each architecture directly, then combine.
release_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
release_root="$PWD/dist/releases/v$release_version"
mkdir -p "$PWD/.build"
release_stage=$(mktemp -d "$PWD/.build/release-stage.XXXXXX")
trap 'rm -rf "$release_stage"' EXIT
mkdir -p "$release_root" "$release_stage/Syndrome.app/Contents/MacOS" "$release_stage/Syndrome.app/Contents/Resources"
release_sdk=$(xcrun --show-sdk-path)
for release_arch in arm64 x86_64; do
    print "Building $release_arch for macOS 14+"
    xcrun swiftc -O -whole-module-optimization -parse-as-library \
        -target "$release_arch-apple-macosx14.0" -sdk "$release_sdk" \
        Sources/SyndromeDSP/*.swift Sources/Syndrome/*.swift \
        -o "$release_stage/Syndrome-$release_arch"
done
xcrun lipo -create "$release_stage/Syndrome-arm64" "$release_stage/Syndrome-x86_64" \
    -output "$release_stage/Syndrome.app/Contents/MacOS/Syndrome"
cp Resources/Info.plist "$release_stage/Syndrome.app/Contents/Info.plist"
cp Resources/Syndrome.icns LICENSE NOTICE "$release_stage/Syndrome.app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$release_stage/Syndrome.app"
/usr/bin/codesign --verify --deep --strict "$release_stage/Syndrome.app"
xcrun lipo "$release_stage/Syndrome.app/Contents/MacOS/Syndrome" -verify_arch arm64 x86_64
rm "$release_stage/Syndrome-arm64" "$release_stage/Syndrome-x86_64"
cp LICENSE NOTICE "$release_stage/"
cp docs/INSTALL_MACOS.md "$release_stage/INSTALL.md"
cp "releases/v$release_version.md" "$release_stage/RELEASE_NOTES.md"
ln -s /Applications "$release_stage/Applications"
/usr/bin/ditto -c -k --sequesterRsrc "$release_stage" "$release_root/Syndrome-$release_version-macOS-universal.zip"
/usr/bin/hdiutil create -quiet -ov -format UDZO -volname "Syndrome $release_version" \
    -srcfolder "$release_stage" "$release_root/Syndrome-$release_version-macOS-universal.dmg"
cp "releases/v$release_version.md" "$release_root/RELEASE_NOTES.md"
(
    cd "$release_root"
    shasum -a 256 "Syndrome-$release_version-macOS-universal.zip" "Syndrome-$release_version-macOS-universal.dmg" > SHA256SUMS.txt
)
print "Release assets: $release_root"
