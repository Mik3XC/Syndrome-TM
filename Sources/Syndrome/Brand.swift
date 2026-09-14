// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct AlienHead: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var path = Path()
        path.move(to: p(0.5, 0.94))
        path.addCurve(to: p(0.08, 0.34), control1: p(0.31, 0.88), control2: p(0.07, 0.57))
        path.addCurve(to: p(0.5, 0.06), control1: p(0.08, 0.12), control2: p(0.27, 0.04))
        path.addCurve(to: p(0.92, 0.34), control1: p(0.73, 0.04), control2: p(0.92, 0.12))
        path.addCurve(to: p(0.5, 0.94), control1: p(0.93, 0.57), control2: p(0.69, 0.88))
        path.closeSubpath()
        return path
    }
}

struct AlienEyes: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var path = Path()
        path.move(to: p(0.19, 0.35))
        path.addCurve(to: p(0.43, 0.62), control1: p(0.40, 0.37), control2: p(0.47, 0.47))
        path.addCurve(to: p(0.19, 0.35), control1: p(0.27, 0.64), control2: p(0.17, 0.51))
        path.closeSubpath()
        path.move(to: p(0.81, 0.35))
        path.addCurve(to: p(0.57, 0.62), control1: p(0.60, 0.37), control2: p(0.53, 0.47))
        path.addCurve(to: p(0.81, 0.35), control1: p(0.73, 0.64), control2: p(0.83, 0.51))
        path.closeSubpath()
        return path
    }
}

struct AlienLogo: View {
    var body: some View {
        ZStack {
            AlienHead().fill(LinearGradient(colors: [Color(red: 0.78, green: 1, blue: 0.40), Color(red: 0.25, green: 0.82, blue: 0.60)], startPoint: .topLeading, endPoint: .bottomTrailing))
            AlienEyes().fill(Color(red: 0.03, green: 0.08, blue: 0.08))
        }.aspectRatio(1, contentMode: .fit).accessibilityLabel("Syndrome alien-head logo")
    }
}

struct SyndromeAppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 220).fill(Color(red: 0.035, green: 0.055, blue: 0.075))
            Circle().stroke(.green.opacity(0.17), lineWidth: 4).padding(95)
            AlienLogo().padding(180)
        }.padding(24).frame(width: 1024, height: 1024)
    }
}
