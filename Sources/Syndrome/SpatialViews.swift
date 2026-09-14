// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

struct SpatialControlView: View {
    @ObservedObject var audio: StudioAudio
    @ObservedObject var space: SpatialController
    let visualsPlaying: Bool
    let canPlay: Bool
    let playLabel: String
    let replay: () -> Void
    @State private var roomView = true
    private var p: SpatialPoint { space.spatialPosition }
    private var extent: Double { max(10, ceil(max(abs(p.x), abs(p.y), abs(p.z), space.balanceRadius) / 10) * 10) }
    private var gain: Double { SpatialModel.gain(at: p, radius: space.balanceRadius) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Spatial sphere", systemImage: "move.3d").font(.title2.bold())
                Spacer()
                Toggle("3D preview", isOn: $audio.spatialEnabled).toggleStyle(.switch)
                Button("Centre") { space.moveSphere(to: .zero) }
                Button("Reset space") { space.resetSpatial() }
            }
            Text("SHARED · SOUND BOARD + SUBVOCAL").font(.caption.bold()).tracking(1).foregroundStyle(.green)
            Text("Speakers / reference at (0, 0, 0). Move the virtual source sphere; the listener stays at the centre, facing −Z. X is left/right, Y is height, Z is front/rear. Each plane has four quadrants; 3D has eight octants and six axis directions.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Spatial view", selection: $roomView) {
                    Text("Room + apparition").tag(true)
                    Text("XYZ planes").tag(false)
                }.pickerStyle(.segmented).frame(maxWidth: 320)
                Spacer()
                Button(playLabel, systemImage: "play.fill", action: replay).disabled(!canPlay).buttonStyle(.borderedProminent).tint(.green)
            }
            if roomView {
                VirtualRoomView(space: space)
            } else {
            HStack(alignment: .top, spacing: 12) {
                plane(.x, .y, "Front · X/Y")
                plane(.x, .z, "Top · X/Z")
                plane(.z, .y, "Side · Z/Y")
            }
            Text("Dashed ring = inner balance sphere · bright ball = virtual source · all axes in metres.")
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                ForEach(SpatialAxis.allCases, id: \.self) { axis in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(axis.rawValue) · \(axis.directions)").font(.caption.weight(.medium))
                        HStack {
                            TextField("\(axis.rawValue) position in metres", value: axisBinding(axis), format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(.roundedBorder).frame(minWidth: 60)
                            Text("m").font(.caption)
                        }
                        Slider(value: axisBinding(axis), in: -50...50, step: 0.1) { Text("\(axis.rawValue) position") }.labelsHidden()
                    }.frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 18) {
                metric("Distance", String(format: "%.2f m", p.distance))
                metric("Region", p.region)
                metric("Azimuth / elevation", "\(degrees(p.azimuthDegrees)) / \(degrees(p.elevationDegrees))")
                metric("Distance gain", String(format: "%.3f× · %.1f dB", gain, 20 * log10(gain)))
            }
            HStack(spacing: 20) {
                control("Inner balance radius", value: $space.balanceRadius, range: 0.25...10, step: 0.25, unit: "m")
                control("Throw travel", value: $space.throwDistance, range: 0.5...50, step: 0.5, unit: "m")
                control("Throw speed", value: $space.throwSpeed, range: 0.5...25, step: 0.5, unit: "m/s")
            }
            HStack(spacing: 8) {
                Text("THROW").font(.caption.bold())
                ForEach(SpatialAxis.allCases, id: \.self) { axis in
                    ForEach([-1.0, 1.0], id: \.self) { sign in
                        Button("\(sign < 0 ? "−" : "+")\(axis.rawValue)") {
                            space.launchSphere(axis: axis, sign: sign)
                            space.pauseThrow(!visualsPlaying)
                        }.help("Translate \(space.throwDistance.formatted()) metres along \(sign < 0 ? "negative" : "positive") \(axis.rawValue), clipped at ±50 metres.")
                        .accessibilityLabel("Throw \(sign < 0 ? "negative" : "positive") \(axis.rawValue)")
                    }
                }
                Spacer()
                Button(space.throwPaused ? "Resume throw" : "Pause throw") { space.pauseThrow(!space.throwPaused) }.disabled(!space.isThrowing)
                Button("Stop throw") { space.stopThrow() }.disabled(!space.isThrowing)
            }
            if let end = space.throwDestination {
                Text("\(space.throwPaused ? "Paused" : "Moving") → (\(f(end.x)), \(f(end.y)), \(f(end.z))) m. Travel is measured from the current position; each coordinate stops at ±50 m.")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Button(playLabel, systemImage: "play.fill", action: replay).disabled(!canPlay).buttonStyle(.borderedProminent).tint(.green)
                Text(audio.spatialEnabled ? audio.spatialRenderer : "3D bypassed · ordinary mono preview").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(audio.isPlaying ? "Preview playing. " : "")Drag or throw while a preview plays to hear movement. Throws alone are silent and finish even after the clip ends. The master Audio switch and level apply to both tabs. Ordinary speech and the carrier use the same sphere.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Distance curve & assumptions") {
                VStack(alignment: .leading, spacing: 12) {
                    let distances = (0...200).map { Double($0) / 2 }
                    Plot(title: "Before / after distance gain", traces: [
                        Trace(name: "Reference gain", x: [0, 100], y: [1, 1], color: .secondary, dashed: true),
                        Trace(name: "Modeled gain", x: distances, y: distances.map { SpatialModel.gain(at: SpatialPoint(x: $0), radius: space.balanceRadius) }, color: .green)
                    ], xRange: 0...100, yRange: 0...1.05, xLabel: "Radial distance (m)", yLabel: "Relative amplitude gain", summary: "Unity gain inside \(space.balanceRadius) metres; radius divided by distance outside. Current gain \(gain).", marker: p.distance)
                    Text("Inner radius R keeps distance gain at 1 for r ≤ R; outside, gain = R/r, with no automatic level compensation. This is an idealized amplitude model, not measured sound pressure. At 343 m/s, the geometric travel-time estimate is \(f(p.distance / 343 * 1000)) ms; playback does not apply propagation delay or Doppler. Reverb, walls and obstacles are excluded.")
                    Text("Headphone 3D uses macOS HRTF filtering for directional cues; a stereo-pan fallback is labeled if needed. Speakers cannot be assumed to reproduce the virtual location. This does not steer a beam, put sound at a remote physical point, or make low-frequency words intelligible. Source waveform plots remain before spatial processing. Range is a separate one-dimensional lesson and bypasses this sphere to avoid double attenuation.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 12)
            }
        }.padding(18).background(.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.green.opacity(0.25)))
    }

    private func plane(_ h: SpatialAxis, _ v: SpatialAxis, _ title: String) -> some View {
        SpatialPlane(space: space, horizontal: h, vertical: v, title: title, extent: extent)
    }
    private func axisBinding(_ axis: SpatialAxis) -> Binding<Double> {
        Binding(get: { p[axis] }, set: { var target = p; target[axis] = $0; space.moveSphere(to: target) })
    }
    private func f(_ value: Double) -> String { String(format: "%.1f", value) }
    private func degrees(_ value: Double?) -> String { value.map { "\(f($0))°" } ?? "—" }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.caption.monospacedDigit().bold()) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func control(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label) · \(f(value.wrappedValue)) \(unit)").font(.caption.monospacedDigit())
            Slider(value: value, in: range, step: step) { Text(label) }.labelsHidden()
        }.frame(maxWidth: .infinity)
    }
}

private struct SpatialPlane: View {
    @ObservedObject var space: SpatialController
    let horizontal: SpatialAxis
    let vertical: SpatialAxis
    let title: String
    let extent: Double
    @State private var dragExtent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            GeometryReader { geometry in
                let side = max(40, min(geometry.size.width - 44, geometry.size.height - 44))
                let box = CGRect(x: (geometry.size.width - side) / 2, y: 20, width: side, height: side)
                let scale = dragExtent ?? extent
                Canvas { context, _ in
                    func point(_ p: SpatialPoint) -> CGPoint {
                        let uv = SpatialModel.projection(p, horizontal: horizontal, vertical: vertical, extent: scale)
                        return CGPoint(x: box.minX + uv.u * box.width, y: box.minY + uv.v * box.height)
                    }
                    func label(_ text: String, _ x: CGFloat, _ y: CGFloat, color: Color = .secondary) {
                        context.draw(Text(text).font(.system(size: 10, design: .monospaced)).foregroundColor(color), at: CGPoint(x: x, y: y))
                    }
                    let origin = point(.zero)
                    context.fill(Path(box), with: .color(.primary.opacity(0.025)))
                    let radius = space.balanceRadius / (2 * scale)
                    let sphere = CGRect(x: origin.x - box.width * radius, y: origin.y - box.height * radius, width: box.width * radius * 2, height: box.height * radius * 2)
                    context.fill(Path(ellipseIn: sphere), with: .color(.green.opacity(0.12)))
                    context.stroke(Path(ellipseIn: sphere), with: .color(.green.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    var axes = Path()
                    axes.move(to: CGPoint(x: box.minX, y: origin.y)); axes.addLine(to: CGPoint(x: box.maxX, y: origin.y))
                    axes.move(to: CGPoint(x: origin.x, y: box.minY)); axes.addLine(to: CGPoint(x: origin.x, y: box.maxY))
                    context.stroke(axes, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                    label("−+", box.minX + 14, box.minY + 12)
                    label("++", box.maxX - 14, box.minY + 12)
                    label("−−", box.minX + 14, box.maxY - 12)
                    label("+−", box.maxX - 14, box.maxY - 12)
                    label("+\(vertical.rawValue)", origin.x, box.minY - 10)
                    label("−\(vertical.rawValue)", origin.x, box.maxY + 12)
                    label("−\(horizontal.rawValue)", box.minX - 15, origin.y)
                    label("+\(horizontal.rawValue)", box.maxX + 10, origin.y)
                    context.draw(Image(systemName: "hifispeaker.fill"), at: origin)
                    label("0 · speaker", origin.x, origin.y + 18)
                    let target = point(space.spatialPosition)
                    var ray = Path(); ray.move(to: origin); ray.addLine(to: target)
                    context.stroke(ray, with: .color(.green.opacity(0.65)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    let dot = CGRect(x: target.x - 7, y: target.y - 7, width: 14, height: 14)
                    context.fill(Path(ellipseIn: dot), with: .radialGradient(Gradient(colors: [.white, .green, .green.opacity(0.5)]), center: CGPoint(x: target.x - 2, y: target.y - 2), startRadius: 0, endRadius: 10))
                    context.stroke(Path(ellipseIn: dot), with: .color(.green), lineWidth: 1)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if dragExtent == nil { dragExtent = extent }
                    let u = min(1, max(0, (value.location.x - box.minX) / box.width))
                    let v = min(1, max(0, (value.location.y - box.minY) / box.height))
                    space.moveSphere(to: SpatialModel.unproject(u: u, v: v, keeping: space.spatialPosition, horizontal: horizontal, vertical: vertical, extent: dragExtent ?? extent))
                }.onEnded { _ in dragExtent = nil })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title) position map")
                .accessibilityValue("\(horizontal.rawValue) \(space.spatialPosition[horizontal]) metres, \(vertical.rawValue) \(space.spatialPosition[vertical]) metres. Use the labeled coordinate fields or sliders to move the sphere.")
            }.frame(height: 190)
            Text("±\(Int(dragExtent ?? extent)) m / axis · drag to move").font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(8).background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity)
    }
}
