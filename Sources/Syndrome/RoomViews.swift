// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

struct VirtualRoomView: View {
    @ObservedObject var space: SpatialController
    @State private var orbit = false
    private var room: VirtualRoom { space.room }
    private var directGain: Double { space.orientation.gainTowardOrigin(from: space.spatialPosition, directional: space.directionalVoice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Virtual room · synthetic point cloud", systemImage: "cube.transparent").font(.headline)
                Spacer()
                Button("Place in room") { space.placeInRoom() }
            }
            HStack {
                Picker("Room interaction", selection: $orbit) {
                    Text("Place apparition").tag(false)
                    Text("Orbit view").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 310)
                Spacer()
                Button("Front view") { space.roomCameraYaw = 0; space.roomCameraElevation = 15 }
                Button("Top view") { space.roomCameraYaw = 0; space.roomCameraElevation = 80 }
                Button("Reset view") { space.roomCameraYaw = 35; space.roomCameraElevation = 30 }
            }
            RoomCanvas(space: space, orbit: orbit).frame(height: 330)
                .background(Color(red: 0.025, green: 0.055, blue: 0.075), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(orbit ? "Drag to orbit the camera. The listener and sound stay fixed; this changes only the view." : "Click or drag to place the apparition in X/Z at its current height. Its head marker is the audio origin. Use the height control for Y; yaw, pitch and roll rotate its body.")
                .font(.caption).foregroundStyle(.secondary)
            if !room.contains(space.spatialPosition) {
                Label("Source is outside the modeled room. XYZ controls and throws still work; Place in room brings it back into view.", systemImage: "arrow.up.right.square")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Text("Voice height above floor").font(.caption)
                TextField("Voice height above floor in metres", value: Binding(get: { space.spatialPosition.y - room.floorY }, set: { value in
                    guard value.isFinite else { return }
                    var p = space.spatialPosition; p.y = min(room.ceilingY - 0.1, max(room.floorY + 0.1, value + room.floorY)); space.moveSphere(to: p)
                }), format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width: 70)
                Text("m").font(.caption)
                Spacer()
                Button("Face listener") { space.orientation = .facingOrigin(from: space.spatialPosition) }
                Button("Reset rotation") { space.orientation = SourceOrientation() }
            }
            HStack(spacing: 18) {
                angle("Yaw · turn", key: \.yaw, range: -180...180)
                angle("Pitch · tilt", key: \.pitch, range: -90...90)
                angle("Roll · lean", key: \.roll, range: -180...180)
            }
            HStack {
                Toggle("Directional voice", isOn: $space.directionalVoice).toggleStyle(.switch)
                Text("Facing gain · \(directGain.formatted(.number.precision(.fractionLength(2))))×").font(.caption.monospacedDigit())
            }
            Text("Directional voice models a broad emission pattern: 1× facing the listener, 0.25× facing away, multiplied by distance gain. Roll rotates the figure but does not change this axially symmetric pattern. The listener is at the central speaker reference, 1.6 m above the floor, facing −Z.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Room dimensions & model") {
                HStack(spacing: 18) {
                    dimension("Width · X", value: $space.roomWidth, range: 3...30)
                    dimension("Depth · Z", value: $space.roomDepth, range: 3...30)
                    dimension("Height · Y", value: $space.roomHeight, range: 2...8)
                }.padding(.top, 10)
                Text("A lidar-style illustration generated from room dimensions. No scan, camera, microphone, tracking or device connection. Walls are visual guides; they do not reflect, block or contain sound in this model. Headphone 3D simulates a virtual source at the apparition; ordinary speakers are not assumed to place sound at that physical location.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

    private func angle(_ label: String, key: WritableKeyPath<SourceOrientation, Double>, range: ClosedRange<Double>) -> some View {
        let value = Binding<Double>(get: { space.orientation[keyPath: key] }, set: { new in
            guard new.isFinite else { return }
            space.orientation[keyPath: key] = min(range.upperBound, max(range.lowerBound, new))
        })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption)
                TextField(label, value: value, format: .number.precision(.fractionLength(0))).textFieldStyle(.roundedBorder).frame(width: 55)
                Text("°").font(.caption)
            }
            Slider(value: value, in: range, step: 1) { Text(label) }.labelsHidden()
        }.frame(maxWidth: .infinity)
    }
    private func dimension(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label) · \(value.wrappedValue.formatted()) m").font(.caption.monospacedDigit())
            Slider(value: value, in: range, step: 0.5) { Text(label) }.labelsHidden()
        }.frame(maxWidth: .infinity)
    }
}

private struct RoomCanvas: View {
    @ObservedObject var space: SpatialController
    let orbit: Bool
    @State private var dragCamera: (yaw: Double, elevation: Double)?
    private var room: VirtualRoom { space.room }

    var body: some View {
        GeometryReader { geometry in
            let transform = RoomScreenTransform(room: room, size: geometry.size, yaw: space.roomCameraYaw, elevation: space.roomCameraElevation)
            let orientation = space.orientation
            Canvas { context, size in
                func point(_ p: SpatialPoint) -> CGPoint { transform.project(p) }
                func line(_ a: SpatialPoint, _ b: SpatialPoint, color: Color, width: Double = 1, dash: [CGFloat] = []) {
                    var path = Path(); path.move(to: point(a)); path.addLine(to: point(b))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
                }
                func dot(_ p: SpatialPoint, color: Color, radius: Double) {
                    let q = point(p)
                    context.fill(Path(ellipseIn: CGRect(x: q.x - radius, y: q.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
                }
                func caption(_ text: String, at p: SpatialPoint, color: Color = .white) {
                    let q = point(p)
                    context.draw(Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(color), at: CGPoint(x: q.x, y: q.y + 14))
                }
                for p in room.pointCloud {
                    dot(p, color: .cyan.opacity(p.y == room.floorY ? 0.4 : 0.16), radius: p.y == room.floorY ? 1.2 : 0.8)
                }
                let corners = room.corners
                for i in 0..<4 {
                    line(corners[i], corners[(i + 1) % 4], color: .cyan.opacity(0.45))
                    line(corners[i + 4], corners[(i + 1) % 4 + 4], color: .cyan.opacity(0.18))
                    line(corners[i], corners[i + 4], color: .cyan.opacity(0.22))
                }
                for (axis, color) in [(SpatialAxis.x, Color.red), (.y, .green), (.z, .blue)] {
                    var endpoint = SpatialPoint.zero; endpoint[axis] = 1
                    line(.zero, endpoint, color: color, width: 2)
                    caption("+\(axis.rawValue)", at: endpoint, color: color)
                }
                // Three great circles show the inner balance sphere in the same world coordinates.
                for plane in 0..<3 {
                    var path = Path()
                    for i in 0...64 {
                        let t = 2 * Double.pi * Double(i) / 64, r = space.balanceRadius
                        let p = plane == 0 ? SpatialPoint(x: r * cos(t), z: r * sin(t)) : (plane == 1 ? SpatialPoint(x: r * cos(t), y: r * sin(t)) : SpatialPoint(y: r * cos(t), z: r * sin(t)))
                        if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) }
                    }
                    context.stroke(path, with: .color(.green.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                dot(.zero, color: .orange, radius: 5)
                caption("SPEAKERS / LISTENER", at: .zero, color: .orange)
                line(.zero, SpatialPoint(z: -0.7), color: .orange, width: 2)
                let source = space.spatialPosition
                line(.zero, source, color: .green.opacity(0.6), dash: [4, 4])
                let floorPoint = SpatialPoint(x: source.x, y: room.floorY, z: source.z)
                line(floorPoint, source, color: .white.opacity(0.4), dash: [2, 4])
                dot(floorPoint, color: .cyan, radius: 3)
                func local(_ p: SpatialPoint) -> SpatialPoint {
                    let rotated = orientation.rotate(p)
                    return SpatialPoint(x: source.x + rotated.x, y: source.y + rotated.y, z: source.z + rotated.z)
                }
                // Original procedural apparition: head, shoulders and a translucent flowing body.
                let outline = [SpatialPoint(x: -0.12, y: -0.18), SpatialPoint(x: -0.4, y: -0.4), SpatialPoint(x: -0.35, y: -0.9), SpatialPoint(x: -0.5, y: -1.5), SpatialPoint(x: -0.15, y: -1.38), SpatialPoint(x: 0.1, y: -1.55), SpatialPoint(x: 0.3, y: -1.4), SpatialPoint(x: 0.5, y: -1.5), SpatialPoint(x: 0.35, y: -0.9), SpatialPoint(x: 0.4, y: -0.4), SpatialPoint(x: 0.12, y: -0.18)]
                var body = Path()
                for (i, p) in outline.enumerated() { if i == 0 { body.move(to: point(local(p))) } else { body.addLine(to: point(local(p))) } }
                body.closeSubpath()
                context.fill(body, with: .color(.mint.opacity(0.22)))
                context.stroke(body, with: .color(.mint.opacity(0.9)), lineWidth: 1.5)
                var head = Path()
                for i in 0...32 {
                    let t = Double(i) * 2 * Double.pi / 32
                    let p = point(local(SpatialPoint(x: 0.18 * cos(t), y: 0.22 * sin(t))))
                    if i == 0 { head.move(to: p) } else { head.addLine(to: p) }
                }
                context.fill(head, with: .color(.mint.opacity(0.3)))
                context.stroke(head, with: .color(.mint), lineWidth: 1.5)
                var profile = Path()
                for i in 0...32 {
                    let t = Double(i) * 2 * Double.pi / 32
                    let p = point(local(SpatialPoint(y: 0.22 * sin(t), z: 0.18 * cos(t))))
                    if i == 0 { profile.move(to: p) } else { profile.addLine(to: p) }
                }
                context.stroke(profile, with: .color(.mint.opacity(0.8)), lineWidth: 1)
                for row in 0..<12 { for column in 0..<16 {
                    let t = Double(column) * 2 * Double.pi / 16
                    let radius = 0.26 + Double(row) * 0.014
                    dot(local(SpatialPoint(x: radius * cos(t), y: -0.3 - Double(row) * 0.1, z: radius * 0.65 * sin(t))), color: .mint.opacity(0.55), radius: 1)
                } }
                line(source, local(SpatialPoint(z: -1)), color: .mint, width: 2)
                line(local(SpatialPoint(x: -0.18, y: -0.12, z: -0.72)), local(SpatialPoint(z: -1)), color: .mint)
                line(local(SpatialPoint(x: 0.18, y: 0.12, z: -0.72)), local(SpatialPoint(z: -1)), color: .mint)
                dot(source, color: .white, radius: 3)
                caption("VOICE ORIGIN", at: local(SpatialPoint(y: 0.5)), color: .mint)
                context.draw(Text("SIMULATED ROOM  /  METRES  /  NO SCAN").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.cyan), at: CGPoint(x: 16, y: 18), anchor: .leading)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if orbit {
                    if dragCamera == nil { dragCamera = (space.roomCameraYaw, space.roomCameraElevation) }
                    guard let start = dragCamera else { return }
                    space.roomCameraYaw = (start.yaw + value.translation.width * 0.4).truncatingRemainder(dividingBy: 360)
                    space.roomCameraElevation = min(80, max(10, start.elevation - value.translation.height * 0.25))
                } else {
                    var p = transform.unproject(value.location, height: space.spatialPosition.y)
                    p.x = min(room.width / 2, max(-room.width / 2, p.x))
                    p.z = min(room.depth / 2, max(-room.depth / 2, p.z))
                    space.moveSphere(to: p)
                }
            }.onEnded { _ in dragCamera = nil })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Virtual room and apparition")
            .accessibilityValue("Synthetic room \(room.width) by \(room.depth) by \(room.height) metres. Voice at X \(space.spatialPosition.x), Y \(space.spatialPosition.y), Z \(space.spatialPosition.z). Yaw \(space.orientation.yaw), pitch \(space.orientation.pitch), roll \(space.orientation.roll) degrees. Use coordinate and rotation controls as alternatives to dragging.")
        }
    }
}

private struct RoomScreenTransform {
    let scale: Double
    let centre: CGPoint
    let worldCentre: CGPoint
    let yaw: Double
    let elevation: Double
    init(room: VirtualRoom, size: CGSize, yaw: Double, elevation: Double) {
        self.yaw = yaw; self.elevation = elevation
        let points = room.corners.map { RoomProjection.project($0, yaw: yaw, elevation: elevation) }
        let minU = points.map(\.u).min()!, maxU = points.map(\.u).max()!
        let minV = points.map(\.v).min()!, maxV = points.map(\.v).max()!
        scale = min(max(1, size.width - 90) / max(1, maxU - minU), max(1, size.height - 75) / max(1, maxV - minV))
        centre = CGPoint(x: size.width / 2, y: size.height / 2 + 8)
        worldCentre = CGPoint(x: (minU + maxU) / 2, y: (minV + maxV) / 2)
    }
    func project(_ p: SpatialPoint) -> CGPoint {
        let uv = RoomProjection.project(p, yaw: yaw, elevation: elevation)
        return CGPoint(x: centre.x + (uv.u - worldCentre.x) * scale, y: centre.y + (uv.v - worldCentre.y) * scale)
    }
    func unproject(_ p: CGPoint, height: Double) -> SpatialPoint {
        RoomProjection.unproject(u: (p.x - centre.x) / scale + worldCentre.x, v: (p.y - centre.y) / scale + worldCentre.y, height: height, yaw: yaw, elevation: elevation)
    }
}
