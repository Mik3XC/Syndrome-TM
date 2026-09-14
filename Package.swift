// swift-tools-version: 5.9
// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "Syndrome",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Syndrome", targets: ["Syndrome"]),
        .executable(name: "SyndromeChecks", targets: ["SyndromeChecks"])
    ],
    targets: [
        .target(name: "SyndromeDSP", linkerSettings: [.linkedFramework("Accelerate")]),
        .executableTarget(name: "Syndrome", dependencies: ["SyndromeDSP"]),
        .executableTarget(name: "SyndromeChecks", dependencies: ["SyndromeDSP"])
    ]
)
