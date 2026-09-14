// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit

@main
struct RenderIcon {
    @MainActor static func main() throws {
        let renderer = ImageRenderer(content: SyndromeAppIcon())
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "SyndromeIcon", code: 1)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
