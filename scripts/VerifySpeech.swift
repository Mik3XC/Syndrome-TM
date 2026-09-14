// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Foundation

@main
struct VerifySpeech {
    @MainActor static func main() async {
        let audio = StudioAudio()
        let message = "Syndrome local speech verification."
        audio.renderSpeech(message)
        for _ in 0..<250 {
            if !audio.rendering { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // AVSpeechSynthesizer may deliver repeated zero-length completion buffers.
        // They must not erase a successfully captured utterance.
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard audio.renderedText == message,
              audio.speechSamples.count > 1000,
              audio.speechSamples.allSatisfy({ $0.isFinite }),
              audio.speechSamples.contains(where: { abs($0) > 0.001 }),
              !audio.isPlaying else {
            print("FAIL: local silent speech rendering: \(audio.status)")
            exit(1)
        }
        guard let track = audio.pitchTrack, track.voicedFraction > 0.05,
              let median = track.medianFrequency, (60...500).contains(median) else {
            print("FAIL: generated speech has no usable pitch track")
            exit(1)
        }
        print("Pitch analysis: \(Int(track.voicedFraction * 100))% voiced, median \(String(format: "%.1f", median)) Hz")
        let count = audio.speechSamples.count
        audio.volume = 0
        audio.playCarrier(frequency: 220, intonationDepth: 1)
        guard !audio.isPlaying else { print("FAIL: carrier bypassed disabled audio"); exit(1) }
        audio.audibleEnabled = true
        guard audio.status.contains("Audio ready") else { print("FAIL: audio toggle status is stale"); exit(1) }
        audio.play(Array(audio.speechSamples.prefix(Int(audio.speechRate * 0.2))), sampleRate: audio.speechRate, label: "muted playback verification")
        guard audio.isPlaying else { print("FAIL: muted playback start: \(audio.status)"); exit(1) }
        for _ in 0..<30 {
            if !audio.isPlaying { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !audio.isPlaying else { audio.stop(); print("FAIL: playback did not finish"); exit(1) }
        audio.playCarrier(frequency: 220, intonationDepth: 1)
        guard audio.isPlaying else { print("FAIL: carrier playback did not start"); exit(1) }
        for _ in 0..<60 {
            if !audio.isPlaying { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !audio.isPlaying else { audio.stop(); print("FAIL: carrier playback did not finish"); exit(1) }
        for distance: Double? in [nil, 5] {
            audio.playRange(frequency: 220, distance: distance, excessLoss: 0)
            guard audio.isPlaying else { print("FAIL: range playback did not start"); exit(1) }
            for _ in 0..<30 {
                if !audio.isPlaying { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !audio.isPlaying else { audio.stop(); print("FAIL: range playback did not finish"); exit(1) }
        }
        audio.playCarrier(frequency: 140.67, intonationDepth: 1)
        audio.space.moveSphere(to: SpatialPoint(x: 3, y: 4, z: -2))
        audio.space.balanceRadius = 2
        guard audio.isPlaying else { print("FAIL: spatial update stopped carrier playback"); exit(1) }
        audio.space.throwDistance = 2; audio.space.throwSpeed = 5
        audio.space.launchSphere(axis: .z, sign: -1)
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard audio.isPlaying && audio.space.spatialPosition.z < -2 else { print("FAIL: live carrier throw"); exit(1) }
        // Replacing a playing buffer must not let its stale completion stop the replacement.
        audio.play(DSP.tone(220, sampleRate: 44100, count: 44100), sampleRate: 44100, label: "muted replacement")
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard audio.isPlaying else { print("FAIL: stale spatial completion stopped new playback"); exit(1) }
        audio.audibleEnabled = false
        guard !audio.isPlaying && !audio.space.isThrowing else { print("FAIL: Audio off did not stop engine/motion"); exit(1) }
        audio.playSpeechPreview(frequency: 140.67, intonationDepth: 1)
        guard !audio.isPlaying else { print("FAIL: clear words bypassed Audio off"); exit(1) }
        audio.audibleEnabled = true
        audio.clearWords = true
        audio.playSpeechPreview(frequency: 140.67, intonationDepth: 1)
        guard audio.isPlaying && audio.status.contains("clear words") else { print("FAIL: clear words preview"); exit(1) }
        audio.space.moveSphere(to: SpatialPoint(x: -2, y: 1, z: -3))
        guard audio.isPlaying else { print("FAIL: spatial clear words stopped"); exit(1) }
        audio.space.orientation = .facingOrigin(from: audio.space.spatialPosition)
        audio.space.directionalVoice = true
        audio.space.orientation.roll = 90
        guard audio.isPlaying else { print("FAIL: apparition rotation stopped clear words"); exit(1) }
        audio.wordDefinition = 0.7
        guard !audio.isPlaying else { print("FAIL: definition change did not stop stale preview"); exit(1) }
        audio.clearWords = false
        audio.playSpeechPreview(frequency: 140.67, intonationDepth: 1)
        guard audio.isPlaying && !audio.status.contains("clear words") else { print("FAIL: carrier-only selection"); exit(1) }
        audio.stop()
        audio.renderSpeech("This render will be cancelled.")
        audio.cancelRender()
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !audio.rendering else { print("FAIL: render cancellation"); exit(1) }
        print("PASS: \(count) speech samples at \(Int(audio.speechRate)) Hz; silent generation, pitch tracking, muted speech/carrier/range/clear-words playback, live spatial movement, output selection, stale-preview cancellation, completion handling and audio-toggle gating.")
    }
}
