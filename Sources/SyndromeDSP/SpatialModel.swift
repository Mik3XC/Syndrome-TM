// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A virtual Cartesian space in metres, not a measured room or a speaker array.
public struct SpatialPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(x: Double = 0, y: Double = 0, z: Double = 0) {
        self.x = x; self.y = y; self.z = z
    }
    public static let zero = SpatialPoint()
    public var distance: Double { sqrt(x * x + y * y + z * z) }
    public subscript(_ axis: SpatialAxis) -> Double {
        get { switch axis { case .x: return x; case .y: return y; case .z: return z } }
        set { switch axis { case .x: x = newValue; case .y: y = newValue; case .z: z = newValue } }
    }
    public var bounded: SpatialPoint {
        func limit(_ v: Double) -> Double { v.isFinite ? min(50, max(-50, v)) : 0 }
        return SpatialPoint(x: limit(x), y: limit(y), z: limit(z))
    }
    public var region: String {
        func sign(_ v: Double) -> String { v == 0 ? "0" : (v > 0 ? "+" : "−") }
        return "X\(sign(x)) Y\(sign(y)) Z\(sign(z))"
    }
    public var azimuthDegrees: Double? { distance < 1e-9 || (x == 0 && z == 0) ? nil : atan2(x, -z) * 180 / .pi }
    public var elevationDegrees: Double? { distance < 1e-9 ? nil : atan2(y, hypot(x, z)) * 180 / .pi }
}

public enum SpatialAxis: String, CaseIterable, Sendable {
    case x = "X", y = "Y", z = "Z"
    public var directions: String {
        switch self { case .x: return "left / right"; case .y: return "down / up"; case .z: return "front / rear" }
    }
}

public enum SpatialModel {
    public static func radius(_ value: Double) -> Double { value.isFinite ? min(10, max(0.25, value)) : 1 }
    public static func gain(at point: SpatialPoint, radius: Double) -> Double {
        let reference = self.radius(radius)
        return reference / max(reference, point.distance.isFinite ? point.distance : 0)
    }
    /// x-right, y-up, z-toward the rear, with the listener facing -Z.
    public static func projection(_ point: SpatialPoint, horizontal: SpatialAxis, vertical: SpatialAxis,
                                  extent: Double) -> (u: Double, v: Double) {
        let scale = max(0.25, extent.isFinite ? extent : 50)
        return (0.5 + point[horizontal] / (2 * scale), 0.5 - point[vertical] / (2 * scale))
    }
    public static func unproject(u: Double, v: Double, keeping point: SpatialPoint,
                                 horizontal: SpatialAxis, vertical: SpatialAxis, extent: Double) -> SpatialPoint {
        var result = point
        let scale = max(0.25, extent.isFinite ? extent : 50)
        result[horizontal] = (u - 0.5) * 2 * scale
        result[vertical] = (0.5 - v) * 2 * scale
        return result.bounded
    }
}

/// A finite, constant-speed translation. No gravity, room collision, Doppler or propagation delay.
public struct SpatialThrow: Sendable {
    public let start: SpatialPoint
    public let end: SpatialPoint
    public let duration: Double
    public init(start: SpatialPoint, axis: SpatialAxis, sign: Double, distance: Double, speed: Double) {
        self.start = start.bounded
        var target = self.start
        let travel = distance.isFinite ? max(0, min(100, distance)) : 0
        target[axis] += (sign < 0 ? -1 : 1) * travel
        self.end = target.bounded
        let actual = abs(self.end[axis] - self.start[axis])
        self.duration = actual / (speed.isFinite ? min(50, max(0.25, speed)) : 1)
    }
    public func position(at elapsed: Double) -> SpatialPoint {
        let t = duration > 0 ? min(1, max(0, elapsed.isFinite ? elapsed / duration : 0)) : 1
        return SpatialPoint(x: start.x + (end.x - start.x) * t,
                            y: start.y + (end.y - start.y) * t,
                            z: start.z + (end.z - start.z) * t)
    }
}

/// Right-handed Euler rotations, applied roll (Z), pitch (X), then yaw (Y).
public struct SourceOrientation: Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double
    public init(yaw: Double = 0, pitch: Double = 0, roll: Double = 0) {
        self.yaw = yaw; self.pitch = pitch; self.roll = roll
    }
    public func rotate(_ p: SpatialPoint) -> SpatialPoint {
        func radians(_ x: Double) -> Double { (x.isFinite ? x : 0) * .pi / 180 }
        let a = radians(yaw), b = radians(pitch), c = radians(roll)
        let x1 = cos(c) * p.x - sin(c) * p.y, y1 = sin(c) * p.x + cos(c) * p.y
        let y2 = cos(b) * y1 - sin(b) * p.z, z2 = sin(b) * y1 + cos(b) * p.z
        return SpatialPoint(x: cos(a) * x1 + sin(a) * z2, y: y2, z: -sin(a) * x1 + cos(a) * z2)
    }
    public var forward: SpatialPoint { rotate(SpatialPoint(z: -1)) }
    public static func facingOrigin(from point: SpatialPoint) -> SourceOrientation {
        guard point.distance > 1e-9 else { return SourceOrientation() }
        return SourceOrientation(yaw: atan2(point.x, point.z) * 180 / .pi,
                                 pitch: asin(max(-1, min(1, -point.y / point.distance))) * 180 / .pi)
    }
    /// Optional, explicitly idealized directional source. Rear gain is 0.25, forward gain 1.
    public func gainTowardOrigin(from point: SpatialPoint, directional: Bool) -> Double {
        guard directional && point.distance > 1e-9 else { return 1 }
        let f = forward
        let cosine = -(f.x * point.x + f.y * point.y + f.z * point.z) / point.distance
        return 0.625 + 0.375 * max(-1, min(1, cosine))
    }
}

public struct VirtualRoom: Equatable, Sendable {
    public var width: Double
    public var depth: Double
    public var height: Double
    public let floorY = -1.6
    public init(width: Double = 8, depth: Double = 10, height: Double = 3) {
        self.width = width.isFinite ? min(30, max(3, width)) : 8
        self.depth = depth.isFinite ? min(30, max(3, depth)) : 10
        self.height = height.isFinite ? min(8, max(2, height)) : 3
    }
    public var ceilingY: Double { floorY + height }
    public var corners: [SpatialPoint] {
        [floorY, ceilingY].flatMap { y in
            [SpatialPoint(x: -width / 2, y: y, z: -depth / 2), SpatialPoint(x: width / 2, y: y, z: -depth / 2),
             SpatialPoint(x: width / 2, y: y, z: depth / 2), SpatialPoint(x: -width / 2, y: y, z: depth / 2)]
        }
    }
    public func contains(_ p: SpatialPoint) -> Bool {
        abs(p.x) <= width / 2 && abs(p.z) <= depth / 2 && (floorY...ceilingY).contains(p.y)
    }
    /// A deterministic synthetic cloud on floor, ceiling and four walls. No sensor data.
    public var pointCloud: [SpatialPoint] {
        let nx = Int(ceil(width / 0.5)), nz = Int(ceil(depth / 0.5)), ny = Int(ceil(height / 0.5))
        var points: [SpatialPoint] = []
        for ix in 0...nx { for iz in 0...nz {
            let x = -width / 2 + width * Double(ix) / Double(nx), z = -depth / 2 + depth * Double(iz) / Double(nz)
            points.append(SpatialPoint(x: x, y: floorY, z: z))
            points.append(SpatialPoint(x: x, y: ceilingY, z: z))
        } }
        for iy in 1..<ny {
            let y = floorY + height * Double(iy) / Double(ny)
            for ix in 0...nx {
                let x = -width / 2 + width * Double(ix) / Double(nx)
                points.append(SpatialPoint(x: x, y: y, z: -depth / 2)); points.append(SpatialPoint(x: x, y: y, z: depth / 2))
            }
            for iz in 1..<nz {
                let z = -depth / 2 + depth * Double(iz) / Double(nz)
                points.append(SpatialPoint(x: -width / 2, y: y, z: z)); points.append(SpatialPoint(x: width / 2, y: y, z: z))
            }
        }
        return points
    }
}

public enum RoomProjection {
    /// Orthographic orbit view in world-metre units. Positive v points down on screen.
    public static func project(_ p: SpatialPoint, yaw: Double, elevation: Double) -> (u: Double, v: Double) {
        let a = yaw * .pi / 180, b = elevation * .pi / 180
        return (cos(a) * p.x - sin(a) * p.z, sin(b) * (sin(a) * p.x + cos(a) * p.z) - cos(b) * p.y)
    }
    public static func unproject(u: Double, v: Double, height: Double, yaw: Double, elevation: Double) -> SpatialPoint {
        let a = yaw * .pi / 180, b = min(80, max(10, elevation)) * .pi / 180
        let depth = (v + cos(b) * height) / sin(b)
        return SpatialPoint(x: cos(a) * u + sin(a) * depth, y: height, z: -sin(a) * u + cos(a) * depth)
    }
}
