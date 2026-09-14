// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Foundation

@main
struct VerifySpatial {
    @MainActor static func main() async throws {
        func require(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL: \(message)"); exit(1) }
        }
        // Offline rendering exercises the actual native mixer with no speaker output.
        func render(_ position: SpatialPoint, radius: Double = 1, hrtf: Bool = false, rate: Double = 44100,
                    orientation: SourceOrientation = SourceOrientation(), directional: Bool = false) throws -> [Double] {
            let graph = SpatialAudioGraph(sampleRate: rate, headphones: hrtf)
            graph.update(position: position, radius: radius, orientation: orientation, directional: directional)
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            try graph.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            let samples = DSP.tone(240, amplitude: 0.5, sampleRate: rate, count: Int(rate))
            graph.source.scheduleBuffer(graph.buffer(samples)!)
            try graph.engine.start(); graph.source.play()
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
            var powers = [0.0, 0.0]
            var frames = 0
            var attempts = 0
            while frames < Int(rate * 0.8) && attempts < 100 {
                let status = try graph.engine.renderOffline(1024, to: output)
                attempts += 1
                if status == .success {
                    // Discard startup filter and parameter-ramp transients.
                    if frames > Int(rate * 0.2) {
                        for c in 0..<2 { for i in 0..<Int(output.frameLength) {
                            let value = Double(output.floatChannelData![c][i])
                            require(value.isFinite, "nonfinite rendered sample")
                            powers[c] += value * value
                        } }
                    }
                    frames += Int(output.frameLength)
                }
            }
            graph.source.stop(); graph.engine.stop()
            require(frames >= Int(rate * 0.8), "offline rendering made no progress")
            require(powers.reduce(0, +) > 1e-6, "spatial render silent at \(rate) Hz")
            return powers
        }
        let centre = try render(.zero)
        require(abs(centre[0] / centre[1] - 1) < 0.01, "centre is not channel-balanced")
        let near = try render(SpatialPoint(z: -1))
        let far = try render(SpatialPoint(z: -2))
        let gainRatio = sqrt(far.reduce(0, +) / near.reduce(0, +))
        require(abs(gainRatio - 0.5) < 0.015, "native inverse attenuation ratio \(gainRatio)")
        let inside = try render(SpatialPoint(z: -0.5))
        require(abs(sqrt(inside.reduce(0, +) / near.reduce(0, +)) - 1) < 0.015, "inside sphere amplifies audio")
        let expanded = try render(SpatialPoint(z: -2), radius: 2)
        require(abs(sqrt(expanded.reduce(0, +) / near.reduce(0, +)) - 1) < 0.015, "balance radius not applied")
        let left = try render(SpatialPoint(x: -1))
        let right = try render(SpatialPoint(x: 1))
        require(left[0] > left[1] * 2 && right[1] > right[0] * 2, "X directions do not pan correctly")
        for rate in [8192.0, 22050, 44100] {
            _ = try render(SpatialPoint(x: 2, y: 3, z: -4), hrtf: true, rate: rate)
        }
        let front = try render(SpatialPoint(z: -1), hrtf: true)
        let rear = try render(SpatialPoint(z: 1), hrtf: true)
        let up = try render(SpatialPoint(y: 1), hrtf: true)
        let down = try render(SpatialPoint(y: -1), hrtf: true)
        require(abs(front.reduce(0, +) - rear.reduce(0, +)) > 0.01, "HRTF front/rear response identical")
        require(abs(up.reduce(0, +) - down.reduce(0, +)) > 0.01, "HRTF height response identical")
        let facing = try render(SpatialPoint(z: -2), orientation: SourceOrientation(yaw: 180), directional: true)
        let away = try render(SpatialPoint(z: -2), directional: true)
        require(abs(sqrt(away.reduce(0, +) / facing.reduce(0, +)) - 0.25) < 0.015, "directional source gain not applied to native output")

        let audio = StudioAudio()
        var updates = 0
        audio.space.onChange = { updates += 1 }
        audio.space.roomCameraYaw = 70
        audio.space.roomWidth = 12
        require(updates == 0, "camera/room drawing changed audio state")
        audio.space.orientation = SourceOrientation(yaw: 40, pitch: 20, roll: 10)
        audio.space.directionalVoice = true
        require(updates == 2, "source orientation/directionality not connected")
        audio.space.resetSpatial()
        audio.space.throwDistance = 1; audio.space.throwSpeed = 5
        audio.space.launchSphere(axis: .x, sign: 1)
        audio.space.pauseThrow(true)
        try await Task.sleep(nanoseconds: 120_000_000)
        require(audio.space.spatialPosition == .zero, "paused throw moved")
        audio.space.pauseThrow(false)
        try await Task.sleep(nanoseconds: 350_000_000)
        require(audio.space.spatialPosition == SpatialPoint(x: 1) && !audio.space.isThrowing, "throw did not finish exactly")
        require(!audio.isPlaying && !audio.audibleEnabled, "throw started audio")
        audio.space.launchSphere(axis: .z, sign: -1)
        audio.stop()
        let stopped = audio.space.spatialPosition
        try await Task.sleep(nanoseconds: 120_000_000)
        require(audio.space.spatialPosition == stopped && !audio.space.isThrowing, "Stop did not cancel motion")
        audio.space.launchSphere(axis: .y, sign: 1)
        audio.space.moveSphere(to: SpatialPoint(x: 3, y: 4, z: -5))
        try await Task.sleep(nanoseconds: 120_000_000)
        require(audio.space.spatialPosition == SpatialPoint(x: 3, y: 4, z: -5), "manual move did not cancel trajectory")
        audio.space.resetSpatial()
        require(audio.space.spatialPosition == .zero && audio.space.balanceRadius == 1, "spatial reset failed")
        print("PASS: native offline stereo balance, inverse-distance gain, inner radius, X panning, HRTF depth/height at studio rates; silent throws, pause/resume, completion, cancellation and reset.")
    }
}
