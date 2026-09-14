// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import Accelerate
import Foundation

public struct Spectrum {
    public let frequencies: [Double]
    public let amplitudes: [Double]
    public let binWidth: Double
    public var peakFrequency: Double { frequencies[amplitudes.indices.max(by: { amplitudes[$0] < amplitudes[$1] })!] }
}

public enum FFTWindow: String, CaseIterable, Sendable {
    case rectangular = "Rectangular"
    case hann = "Hann"
}

public enum DSP {
    public static func tone(_ frequency: Double, amplitude: Double = 1, sampleRate: Double, count: Int, phase: Double = 0) -> [Double] {
        precondition(sampleRate > 0 && count > 0)
        return (0..<count).map { amplitude * cos(2 * .pi * frequency * Double($0) / sampleRate + phase) }
    }

    public static func sum(_ a: [Double], _ b: [Double]) -> [Double] {
        precondition(a.count == b.count)
        return zip(a, b).map(+)
    }

    /// Complex FFT avoids packed real-transform scaling conventions. Forward FFT is unnormalized.
    /// One-sided peak amplitude: 2|X[k]| / sum(window), except DC and Nyquist (factor 1).
    public static func spectrum(_ samples: [Double], sampleRate: Double, window: FFTWindow = .rectangular) -> Spectrum {
        let n = samples.count
        precondition(n >= 2 && n.nonzeroBitCount == 1 && sampleRate > 0)
        let weights = (0..<n).map { i in
            window == .hann ? 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n)) : 1.0
        } // Periodic Hann, coherent gain 0.5.
        var real = zip(samples, weights).map(*)
        var imaginary = [Double](repeating: 0, count: n)
        let logN = vDSP_Length(n.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetupD(logN, FFTRadix(kFFTRadix2)) else { preconditionFailure("FFT setup unavailable") }
        defer { vDSP_destroy_fftsetupD(setup) }
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPDoubleSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zipD(setup, &split, 1, logN, FFTDirection(FFT_FORWARD))
            }
        }
        let gain = weights.reduce(0, +)
        let amplitudes = (0...n / 2).map { k in
            hypot(real[k], imaginary[k]) * ((k == 0 || k == n / 2) ? 1 : 2) / gain
        }
        let binWidth = sampleRate / Double(n)
        return Spectrum(frequencies: (0...n / 2).map { Double($0) * binWidth }, amplitudes: amplitudes, binWidth: binWidth)
    }

    /// First-order high-pass, bilinear transform with prewarped cutoff.
    /// y[n] = b(x[n] - x[n-1]) + a y[n-1]. Zero initial state; cutoff 0 bypasses.
    public static func highPass(_ samples: [Double], cutoff: Double, sampleRate: Double) -> [Double] {
        precondition(cutoff >= 0 && cutoff < sampleRate / 2)
        if cutoff == 0 { return samples }
        let k = tan(.pi * cutoff / sampleRate)
        let b = 1 / (1 + k)
        let a = (1 - k) / (1 + k)
        var previousX = 0.0, previousY = 0.0
        return samples.map { x in
            let y = b * (x - previousX) + a * previousY
            previousX = x
            previousY = y
            return y
        }
    }

    public static func highPassGain(frequency: Double, cutoff: Double, sampleRate: Double) -> Double {
        if cutoff == 0 { return 1 }
        let r = tan(.pi * frequency / sampleRate) / tan(.pi * cutoff / sampleRate)
        return r / sqrt(1 + r * r)
    }

    public static func alias(_ frequency: Double, sampleRate: Double) -> Double {
        let wrapped = abs(frequency).truncatingRemainder(dividingBy: sampleRate)
        return min(wrapped, sampleRate - wrapped)
    }

    public static func nonlinear(_ samples: [Double], strength: Double) -> [Double] {
        samples.map { $0 + strength * $0 * $0 }
    }

    public static func modulation(messageFrequency: Double, carrier: Double, depth: Double, sampleRate: Double, count: Int) -> (original: [Double], am: [Double], ssb: [Double]) {
        let original = sum(tone(messageFrequency, amplitude: 0.5, sampleRate: sampleRate, count: count),
                           tone(messageFrequency + 40, amplitude: 0.5, sampleRate: sampleRate, count: count))
        let c = tone(carrier, sampleRate: sampleRate, count: count)
        let am = zip(original, c).map { (1 + depth * $0.0) * $0.1 }
        // Analytic upper-sideband synthesis; amplitudes match AM's individual upper sidebands.
        let ssb = sum(tone(carrier + messageFrequency, amplitude: depth / 4, sampleRate: sampleRate, count: count),
                      tone(carrier + messageFrequency + 40, amplitude: depth / 4, sampleRate: sampleRate, count: count))
        return (original, am, ssb)
    }
}

public struct RecordingSimulation {
    public static let referenceRate = 8192.0
    public let original: [Double]
    public let filtered: [Double]
    public let sampled: [Double]

    public init(cutoff: Double, sampleRate: Double, count: Int) {
        let referenceRate = Self.referenceRate
        let stride = Int(referenceRate / sampleRate)
        precondition(stride > 0 && Double(stride) * sampleRate == referenceRate)
        let warmup = Int(referenceRate * 2)
        let total = warmup + count * stride
        let source = DSP.sum(DSP.sum(
            DSP.tone(20, amplitude: 0.7, sampleRate: referenceRate, count: total),
            DSP.tone(180, amplitude: 0.35, sampleRate: referenceRate, count: total)),
            DSP.tone(900, amplitude: 0.25, sampleRate: referenceRate, count: total))
        original = Array(source.dropFirst(warmup))
        let filteredValues = Array(DSP.highPass(source, cutoff: cutoff, sampleRate: referenceRate).dropFirst(warmup))
        filtered = filteredValues
        sampled = (0..<count).map { filteredValues[$0 * stride] }
    }
}

public enum SoundPreset: String, CaseIterable, Sendable {
    case sine = "Pure tone", chime = "Orbital chime", beats = "Twin tones", sweep = "Frequency sweep"
    public var detail: String {
        switch self {
        case .sine: return "220 Hz · sine"
        case .chime: return "330 + 660 + 990 Hz · decaying"
        case .beats: return "220 + 224 Hz · 4 Hz envelope"
        case .sweep: return "180 → 880 Hz · linear chirp"
        }
    }
    public func samples(sampleRate: Double, duration: Double = 2, frequency: Double = 220) -> [Double] {
        let count = Int(sampleRate * duration)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let edge = min(1, t / 0.02) * min(1, max(0, (duration - t - 1 / sampleRate) / 0.04))
            let value: Double
            switch self {
            case .sine: value = sin(2 * .pi * frequency * t)
            case .chime: value = (sin(2 * .pi * 330 * t) + 0.5 * sin(2 * .pi * 660 * t) + 0.25 * sin(2 * .pi * 990 * t)) / 1.75 * exp(-2 * t)
            case .beats: value = (sin(2 * .pi * 220 * t) + sin(2 * .pi * 224 * t)) / 2
            case .sweep: value = sin(2 * .pi * (180 * t + 0.5 * (700 / duration) * t * t))
            }
            return value * edge
        }
    }
}

public enum RangeModel {
    /// Ideal free-field pressure-amplitude ratio; reference distance is 1 metre.
    /// Optional excess loss is a user assumption in dB per metre, not a hardware measurement.
    public static func gain(distance: Double, excessLossDBPerMetre: Double) -> Double {
        precondition(distance >= 1 && excessLossDBPerMetre >= 0)
        return pow(10, -excessLossDBPerMetre * (distance - 1) / 20) / distance
    }
    public static func levelChangeDB(distance: Double, excessLossDBPerMetre: Double) -> Double {
        -20 * log10(distance) - excessLossDBPerMetre * (distance - 1)
    }
    public static func delay(distance: Double, speed: Double = 343) -> Double { distance / speed }
}

public struct SubVocalSimulation {
    public static let defaultCarrier = 19.75
    public let carrier: Double
    public let envelope: [Double]
    public let modulated: [Double]
    public let instantaneousFrequencies: [Double]
    public let sampleRate: Double

    /// Short-time RMS of synthesized speech shapes a low-frequency carrier for illustration.
    /// This is an envelope visualization, not an intelligible speech encoding or an emitted signal.
    public init(speech: [Double], speechRate: Double, carrier: Double = Self.defaultCarrier, outputRate: Double = 8192, pitchTrack: SpeechPitchTrack? = nil, intonationDepth: Double = 0) {
        precondition(intonationDepth.isFinite && (0...1).contains(intonationDepth))
        precondition(speechRate > 0 && carrier.isFinite && carrier > 0 && outputRate > 2 * carrier)
        self.carrier = carrier
        sampleRate = outputRate
        guard !speech.isEmpty else { envelope = []; modulated = []; instantaneousFrequencies = []; return }
        let duration = Double(speech.count) / speechRate
        let count = max(1, Int(duration * outputRate))
        let radius = max(1, Int(speechRate * 0.015))
        var prefix = [Double](repeating: 0, count: speech.count + 1)
        for i in speech.indices { prefix[i + 1] = prefix[i] + speech[i] * speech[i] }
        let rms: [Double] = (0..<count).map { i in
            let centre = min(speech.count - 1, Int(Double(i) / outputRate * speechRate))
            let low = max(0, centre - radius), high = min(speech.count, centre + radius + 1)
            return sqrt(max(0, (prefix[high] - prefix[low]) / Double(high - low)))
        }
        let peak = rms.max() ?? 0
        let normalized = rms.map { peak > 0 ? $0 / peak : 0 }
        envelope = normalized
        if intonationDepth == 0 || pitchTrack?.medianFrequency == nil {
            instantaneousFrequencies = [Double](repeating: carrier, count: count)
            modulated = normalized.enumerated().map { i, value in value * sin(2 * .pi * carrier * Double(i) / outputRate) }
        } else {
            var frequencies: [Double] = [], signal: [Double] = []
            frequencies.reserveCapacity(count); signal.reserveCapacity(count)
            let smoothing = 1 - exp(-1 / (0.025 * outputRate))
            var semitones = 0.0, phase = 0.0
            for i in 0..<count {
                let target = (pitchTrack?.semitones(at: Double(i) / outputRate) ?? 0) * intonationDepth
                semitones += smoothing * (target - semitones)
                let frequency = min(outputRate * 0.45, max(0.25, carrier * pow(2, semitones / 12)))
                frequencies.append(frequency)
                signal.append(normalized[i] * sin(phase))
                // Integrate frequency to phase; multiplying f(t) by t would be incorrect FM.
                phase = (phase + 2 * .pi * frequency / outputRate).truncatingRemainder(dividingBy: 2 * .pi)
            }
            instantaneousFrequencies = frequencies
            modulated = signal
        }
    }
}

/// Keep real speech at its original sample rate; the carrier is only a quiet underlay.
public struct ClearSpeechMix {
    public let samples: [Double]
    public let voice: [Double]
    public let sampleRate: Double
    public init(speech: [Double], speechRate: Double, carrier: Double, pitchTrack: SpeechPitchTrack? = nil,
                intonationDepth: Double = 1, definition: Double = 0.5, carrierLevel: Double = 0.06) {
        precondition(speechRate > 2 * carrier && carrier > 0)
        sampleRate = speechRate
        let amount = definition.isFinite ? min(1, max(0, definition)) : 0.5
        let bed = carrierLevel.isFinite ? min(0.25, max(0, carrierLevel)) : 0.06
        let clean = speech.map { $0.isFinite ? $0 : 0 }
        // A gentle presence shelf: x + 0…0.6 * first-order high-pass(x).
        // It retains low-frequency vocal body and lifts high-frequency articulation.
        let high = DSP.highPass(clean, cutoff: min(1200, speechRate * 0.2), sampleRate: speechRate)
        let shaped = zip(clean, high).map { $0 + 0.6 * amount * $1 }
        let peak = shaped.map(abs).max() ?? 0
        let headroom = peak > 0.85 ? 0.85 / peak : 1
        let reserved = shaped.map { $0 * headroom }
        voice = reserved
        guard bed > 0 else { samples = reserved; return }
        let tone = SubVocalSimulation(speech: clean, speechRate: speechRate, carrier: carrier,
                                     outputRate: speechRate, pitchTrack: pitchTrack, intonationDepth: intonationDepth)
        samples = reserved.indices.map { i in
            (1 - bed) * reserved[i] + bed * (i < tone.modulated.count ? tone.modulated[i] : 0)
        }
    }
}

public enum PCMEncoding {
    public static func wav(samples: [Double], sampleRate: Int) -> Data {
        precondition(sampleRate > 0 && samples.count < Int(UInt32.max / 2) - 44)
        var data = Data()
        func text(_ string: String) { data.append(contentsOf: string.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) { u16(UInt16(value & 65535)); u16(UInt16(value >> 16)) }
        text("RIFF"); u32(UInt32(36 + samples.count * 2)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(samples.count * 2))
        for value in samples {
            let clamped = value.isFinite ? max(-1, min(1, value)) : 0
            u16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return data
    }
}


public enum MasterFrequency {
    public static let limits: ClosedRange<Double> = 0.5...2000
    public static let presets: [Double] = [0.5, 1, 5, 10, 15, 19.75, 20, 40, 80, 220, 440, 1000, 2000]
    public static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return SubVocalSimulation.defaultCarrier }
        return (min(limits.upperBound, max(limits.lowerBound, value)) * 100).rounded() / 100
    }
    public static func position(_ frequency: Double) -> Double {
        log(normalized(frequency) / limits.lowerBound) / log(limits.upperBound / limits.lowerBound)
    }
    public static func frequency(at position: Double) -> Double {
        normalized(limits.lowerBound * pow(limits.upperBound / limits.lowerBound, min(1, max(0, position))))
    }
    public static func timeSpanMS(_ frequency: Double) -> Double {
        min(4000, max(4, 4000 / normalized(frequency)))
    }
}


extension DSP {
    /// Fade only the edges; retain simulation amplitude and do not normalize range loss away.
    public static func faded(_ samples: [Double], sampleRate: Double, seconds: Double = 0.02) -> [Double] {
        precondition(sampleRate > 0 && seconds > 0)
        guard samples.count > 1 else { return samples.map { _ in 0 } }
        let ramp = min(samples.count / 2, max(1, Int(sampleRate * seconds)))
        return samples.enumerated().map { i, value in
            let edge = min(1, Double(min(i, samples.count - 1 - i)) / Double(ramp))
            return value * edge
        }
    }
}

public struct PitchFrame: Sendable {
    public let time: Double
    public let frequency: Double?
    public let confidence: Double
}

public struct SpeechPitchTrack: Sendable {
    public let frames: [PitchFrame]
    public let medianFrequency: Double?
    public var voicedFraction: Double { frames.isEmpty ? 0 : Double(frames.filter { $0.frequency != nil }.count) / Double(frames.count) }
    public let hopSeconds = 0.01

    /// Educational autocorrelation tracker, 60–500 Hz. Confidence is periodicity, not a probability.
    public init(speech: [Double], sampleRate: Double) {
        precondition(sampleRate > 0)
        guard !speech.isEmpty else { frames = []; medianFrequency = nil; return }
        let analysisRate = 4000.0
        // Two one-pole low-pass stages before resampling suppress high-frequency speech detail.
        let coefficient = 1 - exp(-2 * .pi * 800 / sampleRate)
        var first = 0.0, second = 0.0
        let filtered = speech.map { x -> Double in
            first += coefficient * (x - first)
            second += coefficient * (first - second)
            return second
        }
        let count = max(1, Int(Double(speech.count) / sampleRate * analysisRate))
        let reduced = (0..<count).map { i -> Double in
            let position = Double(i) * sampleRate / analysisRate
            let low = min(filtered.count - 1, Int(position))
            let high = min(filtered.count - 1, low + 1)
            return filtered[low] + (filtered[high] - filtered[low]) * (position - Double(low))
        }
        let frameSize = 240, hop = 40, minLag = 8, maxLag = 67
        let peak = reduced.map { abs($0) }.max() ?? 0
        var measured: [PitchFrame] = []
        for centre in stride(from: 0, to: reduced.count, by: hop) {
            var frame = (0..<frameSize).map { j -> Double in
                let index = centre + j - frameSize / 2
                return reduced.indices.contains(index) ? reduced[index] : 0
            }
            let mean = frame.reduce(0, +) / Double(frameSize)
            frame = frame.map { $0 - mean }
            let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Double(frameSize))
            var correlations = [Double](repeating: 0, count: maxLag + 2)
            if rms > max(0.00001, peak * 0.015) {
                frame.withUnsafeBufferPointer { buffer in
                    for lag in (minLag - 1)...(maxLag + 1) {
                        let n = vDSP_Length(frameSize - lag)
                        var dot = 0.0, e1 = 0.0, e2 = 0.0
                        let a = buffer.baseAddress!, b = a + lag
                        vDSP_dotprD(a, 1, b, 1, &dot, n)
                        vDSP_dotprD(a, 1, a, 1, &e1, n)
                        vDSP_dotprD(b, 1, b, 1, &e2, n)
                        correlations[lag] = dot / max(1e-15, sqrt(e1 * e2))
                    }
                }
            }
            let candidates = (minLag...maxLag).filter { correlations[$0] >= correlations[$0 - 1] && correlations[$0] >= correlations[$0 + 1] }
            // Compare interpolated peak heights: raw integer-lag peaks unfairly penalize
            // non-integer periods and can select an octave-low integer multiple instead.
            let peaks = candidates.map { lag -> (lag: Int, offset: Double, height: Double) in
                let left = correlations[lag - 1], middle = correlations[lag], right = correlations[lag + 1]
                let denominator = left - 2 * middle + right
                let offset = abs(denominator) > 1e-12 ? max(-0.5, min(0.5, 0.5 * (left - right) / denominator)) : 0
                let height = min(1, middle - 0.25 * (left - right) * offset)
                return (lag, offset, height)
            }
            let best = peaks.map(\.height).max() ?? 0
            if best >= 0.65, let peak = peaks.first(where: { $0.height >= best * 0.98 }) {
                let lag = peak.lag, offset = peak.offset
                let frequency = analysisRate / (Double(lag) + offset)
                measured.append(PitchFrame(time: Double(centre) / analysisRate,
                                           frequency: (60...500).contains(frequency) ? frequency : nil, confidence: peak.height))
            } else {
                measured.append(PitchFrame(time: Double(centre) / analysisRate, frequency: nil, confidence: max(0, best)))
            }
        }
        frames = measured
        let voiced = measured.compactMap(\.frequency).sorted()
        medianFrequency = voiced.isEmpty ? nil : voiced[voiced.count / 2]
    }

    /// Interpolate relative pitch in semitones. Unvoiced frames return toward the centre tone.
    public func semitones(at time: Double) -> Double {
        guard let medianFrequency, !frames.isEmpty else { return 0 }
        let position = max(0, time / hopSeconds)
        let low = min(frames.count - 1, Int(position)), high = min(frames.count - 1, low + 1)
        func offset(_ index: Int) -> Double {
            guard let f = frames[index].frequency else { return 0 }
            return max(-12, min(12, 12 * log2(f / medianFrequency)))
        }
        return offset(low) + (offset(high) - offset(low)) * min(1, position - Double(low))
    }
}
