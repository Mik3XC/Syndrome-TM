// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SyndromeDSP

var failures = 0
var checks = 0
func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(name)") }
}
func near(_ name: String, _ actual: Double, _ expected: Double, tolerance: Double = 1e-9) {
    check("\(name): got \(actual), expected \(expected)", abs(actual - expected) < tolerance)
}
func amplitude(_ spectrum: Spectrum, _ frequency: Double) -> Double {
    spectrum.amplitudes[Int((frequency / spectrum.binWidth).rounded())]
}
func peaks(_ spectrum: Spectrum, threshold: Double = 1e-8) -> [Double] {
    zip(spectrum.frequencies, spectrum.amplitudes).filter { $0.1 > threshold }.map { $0.0 }
}

// Non-unit bin spacing guards against confusing sample index and hertz.
for rate in [1024.0, 2048.0, 44100.0, 48000.0] {
    for n in [256, 1024, 2048] {
        let frequency = 17 * rate / Double(n)
        for window in FFTWindow.allCases {
            let result = DSP.spectrum(DSP.tone(frequency, amplitude: 0.73, sampleRate: rate, count: n, phase: 0.3), sampleRate: rate, window: window)
            near("axis spacing", result.binWidth, rate / Double(n))
            near("Nyquist endpoint", result.frequencies.last!, rate / 2)
            check("one-sided bin count", result.amplitudes.count == n / 2 + 1)
            near("frequency peak", result.peakFrequency, frequency)
            near("peak-amplitude normalization \(window)", amplitude(result, frequency), 0.73)
        }
    }
}
let dc = DSP.spectrum([Double](repeating: 0.4, count: 1024), sampleRate: 1024)
near("DC not doubled", dc.amplitudes[0], 0.4)
let nyquist = DSP.spectrum(DSP.tone(512, amplitude: 0.6, sampleRate: 1024, count: 1024), sampleRate: 1024)
near("Nyquist not doubled", nyquist.amplitudes.last!, 0.6)
check("silence finite", DSP.spectrum([Double](repeating: 0, count: 256), sampleRate: 1024).amplitudes.allSatisfy { $0 == 0 && $0.isFinite })

let mod = DSP.modulation(messageFrequency: 60, carrier: 400, depth: 0.8, sampleRate: 2048, count: 2048)
let base = DSP.spectrum(mod.original, sampleRate: 2048)
let am = DSP.spectrum(mod.am, sampleRate: 2048)
let ssb = DSP.spectrum(mod.ssb, sampleRate: 2048)
check("original exact peaks", peaks(base) == [60, 100])
check("AM exact peaks", peaks(am) == [300, 340, 400, 460, 500])
check("SSB exact peaks and suppressed carrier", peaks(ssb) == [460, 500])
near("AM carrier", amplitude(am, 400), 1)
for f in [300.0, 340, 460, 500] { near("AM sideband \(f)", amplitude(am, f), 0.2) }
for f in [460.0, 500] { near("SSB sideband \(f)", amplitude(ssb, f), 0.2) }
near("translation preserves spacing", peaks(ssb).last! - peaks(ssb).first!, peaks(base).last! - peaks(base).first!)
let unmod = DSP.modulation(messageFrequency: 60, carrier: 400, depth: 0, sampleRate: 2048, count: 2048)
check("zero-depth AM only carrier", peaks(DSP.spectrum(unmod.am, sampleRate: 2048)) == [400])
check("zero-depth SSB silent", unmod.ssb.allSatisfy { $0 == 0 })

let linear = DSP.sum(DSP.tone(128, sampleRate: 2048, count: 2048), DSP.tone(136, sampleRate: 2048, count: 2048))
let linearSpectrum = DSP.spectrum(linear, sampleRate: 2048)
check("linear beats contain only original tones", peaks(linearSpectrum) == [128, 136])
near("no difference line in linear sum", amplitude(linearSpectrum, 8), 0)
let identity = (0..<2048).map { i -> Double in
    let t = Double(i) / 2048
    return 2 * cos(.pi * 8 * t) * cos(.pi * 264 * t)
}
check("beat identity pointwise", zip(linear, identity).allSatisfy { abs($0 - $1) < 1e-10 })
let nonlinear = DSP.spectrum(DSP.nonlinear(linear, strength: 0.5), sampleRate: 2048)
check("nonlinear exact peaks", peaks(nonlinear) == [0, 8, 128, 136, 256, 264, 272])
for f in [0.0, 8, 264] { near("nonlinear component \(f)", amplitude(nonlinear, f), 0.5) }
for f in [256.0, 272] { near("second harmonic \(f)", amplitude(nonlinear, f), 0.25) }
check("nonlinearity zero is identity", DSP.nonlinear(linear, strength: 0) == linear)

let filterRate = 8192.0
for cutoff in [5.0, 60.0, 200.0] {
    for frequency in [20.0, 180.0, 900.0, cutoff] {
        let input = DSP.tone(frequency, sampleRate: filterRate, count: 24576)
        let output = Array(DSP.highPass(input, cutoff: cutoff, sampleRate: filterRate).suffix(8192))
        let measured = amplitude(DSP.spectrum(output, sampleRate: filterRate), frequency)
        near("filter analytic gain cutoff \(cutoff) frequency \(frequency)", measured, DSP.highPassGain(frequency: frequency, cutoff: cutoff, sampleRate: filterRate), tolerance: 1e-7)
    }
    near("cutoff -3dB", DSP.highPassGain(frequency: cutoff, cutoff: cutoff, sampleRate: filterRate), 1 / sqrt(2))
    let output = DSP.highPass([Double](repeating: 1, count: 24576), cutoff: cutoff, sampleRate: filterRate)
    check("DC rejection", abs(output.last!) < 1e-9)
}
check("bypass exact", DSP.highPass(linear, cutoff: 0, sampleRate: 2048) == linear)
check("low frequency attenuated more", DSP.highPassGain(frequency: 20, cutoff: 60, sampleRate: 8192) < DSP.highPassGain(frequency: 900, cutoff: 60, sampleRate: 8192))

for rate in [1024.0, 2048.0, 4096.0] {
    let sim = RecordingSimulation(cutoff: 0, sampleRate: rate, count: Int(rate))
    let result = DSP.spectrum(sim.sampled, sampleRate: rate)
    let alias = DSP.alias(900, sampleRate: rate)
    check("recording source reference duration", sim.original.count == 8192)
    check("sampling exact peaks at \(rate)", peaks(result) == [20, 180, alias].sorted())
    near("aliased peak amplitude", amplitude(result, alias), 0.25)
    let filtered = RecordingSimulation(cutoff: 60, sampleRate: rate, count: Int(rate))
    let filteredSpectrum = DSP.spectrum(filtered.sampled, sampleRate: rate)
    near("pipeline attenuation", amplitude(filteredSpectrum, 20), 0.7 * DSP.highPassGain(frequency: 20, cutoff: 60, sampleRate: 8192), tolerance: 1e-8)
}
near("900 at 1024 aliases to 124", DSP.alias(900, sampleRate: 1024), 124)
near("multiple wraps", DSP.alias(2948, sampleRate: 1024), 124)
near("negative frequency alias", DSP.alias(-900, sampleRate: 1024), 124)

// Window leakage and observation length: no randomized fixtures or hardware access.
let offBin = DSP.tone(64.5, sampleRate: 1024, count: 1024)
let rectangular = DSP.spectrum(offBin, sampleRate: 1024)
let hann = DSP.spectrum(offBin, sampleRate: 1024, window: .hann)
check("Hann suppresses distant leakage", amplitude(hann, 100) < amplitude(rectangular, 100) / 100)
let short = DSP.spectrum(DSP.tone(64, sampleRate: 2048, count: 256), sampleRate: 2048)
let long = DSP.spectrum(DSP.tone(64, sampleRate: 2048, count: 2048), sampleRate: 2048)
near("short spacing", short.binWidth, 8)
near("long spacing", long.binWidth, 1)
near("window length preserves centered amplitude", amplitude(short, 64), amplitude(long, 64))
// Sound board and local preview data.
for preset in SoundPreset.allCases {
    let samples = preset.samples(sampleRate: 4096)
    check("pad duration", samples.count == 8192)
    check("pad bounded and finite", samples.allSatisfy { $0.isFinite && abs($0) <= 1.000001 })
    near("pad fade start", samples.first!, 0)
    near("pad fade end", samples.last!, 0)
}
let padTone = DSP.spectrum(SoundPreset.sine.samples(sampleRate: 4096), sampleRate: 4096, window: .hann)
near("audible pad peak", padTone.peakFrequency, 220)
let padChime = DSP.spectrum(SoundPreset.chime.samples(sampleRate: 4096), sampleRate: 4096, window: .hann)
near("chime fundamental", padChime.peakFrequency, 330)
let padBeats = DSP.spectrum(SoundPreset.beats.samples(sampleRate: 4096), sampleRate: 4096, window: .hann)
near("pad beat lower tone", amplitude(padBeats, 220), 0.5, tolerance: 0.01)
near("pad beat upper tone", amplitude(padBeats, 224), 0.5, tolerance: 0.01)
near("pad has no physical difference tone", amplitude(padBeats, 4), 0, tolerance: 1e-5)

// Explicit range assumptions, independent of physical hardware.
near("range reference", RangeModel.gain(distance: 1, excessLossDBPerMetre: 0), 1)
near("doubling distance halves pressure", RangeModel.gain(distance: 2, excessLossDBPerMetre: 0), 0.5)
near("doubling distance -6.02 dB", RangeModel.levelChangeDB(distance: 2, excessLossDBPerMetre: 0), -6.020599913279624)
near("tenfold distance -20 dB", RangeModel.levelChangeDB(distance: 10, excessLossDBPerMetre: 0), -20)
near("specified excess loss", RangeModel.levelChangeDB(distance: 11, excessLossDBPerMetre: 0.5), -20 * log10(11) - 5)
near("propagation one second", RangeModel.delay(distance: 343), 1)
for distance in [1.0, 5, 50, 100] {
    for loss in [0.0, 0.1, 0.5] {
        let gain = RangeModel.gain(distance: distance, excessLossDBPerMetre: loss)
        check("range finite bounded", gain > 0 && gain <= 1)
        near("range dB and pressure consistent", 20 * log10(gain), RangeModel.levelChangeDB(distance: distance, excessLossDBPerMetre: loss))
    }
}

// 19.75 Hz silent envelope illustration: silence and a constant envelope are exact fixtures.
let emptySpeech = SubVocalSimulation(speech: [], speechRate: 22050)
check("empty speech simulation", emptySpeech.envelope.isEmpty && emptySpeech.modulated.isEmpty)
let silentSpeech = SubVocalSimulation(speech: [Double](repeating: 0, count: 2048), speechRate: 2048)
check("silent speech does not emit a carrier", silentSpeech.modulated.allSatisfy { $0 == 0 })
let constantSpeech = SubVocalSimulation(speech: [Double](repeating: 0.4, count: 8192), speechRate: 2048, outputRate: 512)
check("simulation sample count matches duration", constantSpeech.modulated.count == 2048)
check("constant normalized envelope", constantSpeech.envelope.allSatisfy { abs($0 - 1) < 1e-9 })
let carrierSpectrum = DSP.spectrum(constantSpeech.modulated, sampleRate: 512)
near("exact 19.75 Hz carrier", carrierSpectrum.peakFrequency, 19.75)
near("carrier amplitude", amplitude(carrierSpectrum, 19.75), 1)

let waveData = PCMEncoding.wav(samples: [0, 1, -1, 2, -2, .nan], sampleRate: 22050)
check("PCM RIFF header", String(data: waveData.prefix(4), encoding: .utf8) == "RIFF")
check("PCM format header", String(data: waveData[8..<12], encoding: .utf8) == "WAVE")
check("PCM mono data length", waveData.count == 44 + 12)
check("PCM positive full scale", Array(waveData[46..<48]) == [255, 127])
check("PCM negative full scale", Array(waveData[48..<50]) == [1, 128])
check("PCM clips upper bound", Array(waveData[50..<52]) == [255, 127])
check("PCM clips lower bound", Array(waveData[52..<54]) == [1, 128])
check("PCM nonfinite becomes zero", Array(waveData[54..<56]) == [0, 0])

// Master frequency: bounds, log control, numerical precision, and actual spectral output.
near("master lower clamp", MasterFrequency.normalized(-5), 0.5)
near("master upper clamp", MasterFrequency.normalized(9999), 2000)
near("master nonfinite fallback", MasterFrequency.normalized(.nan), 19.75)
near("master hundredth-hertz rounding", MasterFrequency.normalized(12.346), 12.35)
near("slider low endpoint", MasterFrequency.frequency(at: 0), 0.5)
near("slider high endpoint", MasterFrequency.frequency(at: 1), 2000)
for frequency in MasterFrequency.presets {
    near("log slider round trip at \(frequency)", MasterFrequency.frequency(at: MasterFrequency.position(frequency)), frequency)
    let sim = SubVocalSimulation(speech: [Double](repeating: 0.5, count: 8192), speechRate: 2048, carrier: frequency)
    let spec = DSP.spectrum(sim.modulated, sampleRate: sim.sampleRate)
    near("selected carrier retained", sim.carrier, frequency)
    near("selected carrier spectral peak", spec.peakFrequency, frequency)
    near("selected carrier amplitude", amplitude(spec, frequency), 1, tolerance: 1e-8)
    check("simulation remains below Nyquist", frequency < sim.sampleRate / 2)
    let pad = SoundPreset.sine.samples(sampleRate: 8192, duration: 8, frequency: frequency)
    let padSpectrum = DSP.spectrum(pad, sampleRate: 8192, window: .hann)
    near("master tone pad peak", padSpectrum.peakFrequency, frequency)
    check("master tone finite and bounded", pad.allSatisfy { $0.isFinite && abs($0) <= 1 })
    check("plot span includes multiple cycles", MasterFrequency.timeSpanMS(frequency) * frequency / 1000 >= 2)
}
let fractional = SubVocalSimulation(speech: [Double](repeating: 1, count: 2048), speechRate: 2048, carrier: 7.13)
let sampleIndex = 321
near("non-bin-centred frequency is not snapped to FFT bins", fractional.modulated[sampleIndex], sin(2 * .pi * 7.13 * Double(sampleIndex) / fractional.sampleRate))

let fadeInput = [Double](repeating: 0.2, count: 100)
let fadeOutput = DSP.faded(fadeInput, sampleRate: 1000, seconds: 0.01)
check("simulation fade length", fadeOutput.count == fadeInput.count)
near("simulation fade begins at zero", fadeOutput.first!, 0)
near("simulation fade ends at zero", fadeOutput.last!, 0)
near("simulation fade preserves interior attenuation", fadeOutput[50], 0.2)
check("simulation fade does not amplify", zip(fadeInput, fadeOutput).allSatisfy { abs($1) <= abs($0) })
check("simulation fade empty", DSP.faded([], sampleRate: 1000).isEmpty)
check("simulation fade one sample", DSP.faded([1], sampleRate: 1000) == [0])
check("simulation fade finite", fadeOutput.allSatisfy { $0.isFinite })

// Pitch extraction and prosody mapping from known signals, without microphone input.
for pitch in [80.0, 125, 200, 320, 450] {
    let voiced = DSP.tone(pitch, amplitude: 0.7, sampleRate: 16000, count: 16000)
    let track = SpeechPitchTrack(speech: voiced, sampleRate: 16000)
    check("pitch tracker finds periodic voice", track.voicedFraction > 0.9)
    near("pitch tracker known frequency \(pitch)", track.medianFrequency ?? 0, pitch, tolerance: pitch * 0.02)
}
let harmonicVoice = DSP.sum(DSP.tone(120, amplitude: 0.5, sampleRate: 16000, count: 16000), DSP.tone(240, amplitude: 0.8, sampleRate: 16000, count: 16000))
near("harmonic voice tracks fundamental", SpeechPitchTrack(speech: harmonicVoice, sampleRate: 16000).medianFrequency ?? 0, 120, tolerance: 2)
let noPitch = SpeechPitchTrack(speech: [Double](repeating: 0, count: 16000), sampleRate: 16000)
check("silence has no pitch", noPitch.medianFrequency == nil && noPitch.voicedFraction == 0)
var seed: UInt64 = 1234567
let unvoicedNoise = (0..<16000).map { _ -> Double in
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 33) / Double(UInt64(1) << 31) * 2 - 1
}
check("noise is mostly unvoiced", SpeechPitchTrack(speech: unvoicedNoise, sampleRate: 16000).voicedFraction < 0.1)
let risingVoice = (0..<32000).map { i -> Double in
    let t = Double(i) / 16000
    return 0.7 * sin(2 * .pi * (100 * t + 40 * t * t))
}
let risingTrack = SpeechPitchTrack(speech: risingVoice, sampleRate: 16000)
check("rising contour detected", risingTrack.voicedFraction > 0.85)
for t in [0.4, 0.8, 1.2, 1.6] {
    let frame = risingTrack.frames.min(by: { abs($0.time - t) < abs($1.time - t) })!
    near("known changing pitch at \(t)", frame.frequency ?? 0, 100 + 80 * t, tolerance: 8)
}
let prosody = SubVocalSimulation(speech: risingVoice, speechRate: 16000, carrier: 20, pitchTrack: risingTrack, intonationDepth: 1)
let early = prosody.instantaneousFrequencies[Int(0.5 * prosody.sampleRate)]
let late = prosody.instantaneousFrequencies[Int(1.5 * prosody.sampleRate)]
check("rising intonation bends carrier upward", late > early * 1.4)
near("relative pitch motion retained", late / early, 220.0 / 140, tolerance: 0.1)
check("prosody remains bounded", prosody.modulated.allSatisfy { $0.isFinite && abs($0) <= 1 })
check("pitch mapping does not compress duration", prosody.modulated.count == 16384)
let flat = SubVocalSimulation(speech: risingVoice, speechRate: 16000, carrier: 20, pitchTrack: risingTrack, intonationDepth: 0)
let previousMode = SubVocalSimulation(speech: risingVoice, speechRate: 16000, carrier: 20)
check("zero strength reproduces cadence-only mode exactly", flat.modulated == previousMode.modulated)
check("cadence-only frequency constant", flat.instantaneousFrequencies.allSatisfy { $0 == 20 })
let noPitchFallback = SubVocalSimulation(speech: risingVoice, speechRate: 16000, carrier: 20, pitchTrack: noPitch, intonationDepth: 1)
check("unavailable pitch falls back without fabricating contour", noPitchFallback.modulated == previousMode.modulated)
var expectedPhase = 0.0
var phaseError = 0.0
for i in prosody.modulated.indices {
    phaseError = max(phaseError, abs(prosody.modulated[i] - prosody.envelope[i] * sin(expectedPhase)))
    expectedPhase += 2 * .pi * prosody.instantaneousFrequencies[i] / prosody.sampleRate
}
check("FM integrates frequency to continuous phase", phaseError < 1e-9)
for centre in [0.5, 2000.0] {
    let bounded = SubVocalSimulation(speech: risingVoice, speechRate: 16000, carrier: centre, pitchTrack: risingTrack, intonationDepth: 1)
    check("mapped frequencies positive and below Nyquist", bounded.instantaneousFrequencies.allSatisfy { $0 >= 0.25 && $0 <= bounded.sampleRate * 0.45 })
}
let gapped = (0..<32000).map { i -> Double in
    let t = Double(i) / 16000
    return t > 0.75 && t < 1.25 ? 0 : 0.5 * sin(2 * .pi * 160 * t)
}
let gapTrack = SpeechPitchTrack(speech: gapped, sampleRate: 16000)
check("unvoiced gap remains unvoiced", gapTrack.frames.filter { $0.time > 0.9 && $0.time < 1.1 }.allSatisfy { $0.frequency == nil })
let gapSimulation = SubVocalSimulation(speech: gapped, speechRate: 16000, carrier: 20, pitchTrack: gapTrack, intonationDepth: 1)
near("cadence silence preserved", gapSimulation.modulated[Int(gapSimulation.sampleRate)], 0)

// Cartesian geometry, projection inversion and finite throws are independent of audio hardware.
let spatialOrigin = SpatialPoint.zero
near("origin distance", spatialOrigin.distance, 0)
check("origin direction undefined", spatialOrigin.azimuthDegrees == nil && spatialOrigin.elevationDegrees == nil)
near("3D distance", SpatialPoint(x: 3, y: 4, z: 12).distance, 13)
near("right azimuth", SpatialPoint(x: 1).azimuthDegrees ?? -999, 90)
near("front azimuth", SpatialPoint(z: -1).azimuthDegrees ?? -999, 0)
near("up elevation", SpatialPoint(y: 1).elevationDegrees ?? -999, 90)
check("axis planes explicitly zero", SpatialPoint(x: 1, y: -1).region == "X+ Y− Z0")
var regions = Set<String>()
for x in [-1.0, 1] { for y in [-1.0, 1] { for z in [-1.0, 1] {
    let p = SpatialPoint(x: x, y: y, z: z)
    regions.insert(p.region)
    near("symmetric octant gain", SpatialModel.gain(at: p, radius: 1), 1 / sqrt(3))
} } }
check("eight distinct octants", regions.count == 8)
for axes: (SpatialAxis, SpatialAxis) in [(.x, .y), (.x, .z), (.z, .y)] {
    let p = SpatialPoint(x: 3, y: -4, z: 7)
    let uv = SpatialModel.projection(p, horizontal: axes.0, vertical: axes.1, extent: 10)
    let back = SpatialModel.unproject(u: uv.u, v: uv.v, keeping: p, horizontal: axes.0, vertical: axes.1, extent: 10)
    for axis in SpatialAxis.allCases { near("projection roundtrip including held axis", back[axis], p[axis]) }
    let topRight = SpatialModel.unproject(u: 1, v: 0, keeping: p, horizontal: axes.0, vertical: axes.1, extent: 10)
    near("right maps positive", topRight[axes.0], 10)
    near("top maps positive", topRight[axes.1], 10)
}
for radius in [0.25, 1, 10.0] {
    for r in [0, radius / 2, radius] { near("no inner distance boost", SpatialModel.gain(at: SpatialPoint(x: r), radius: radius), 1) }
    near("double reference halves amplitude", SpatialModel.gain(at: SpatialPoint(z: -2 * radius), radius: radius), 0.5)
    near("distance doubling minus six dB", 20 * log10(SpatialModel.gain(at: SpatialPoint(y: 2 * radius), radius: radius)), -6.020599913279624)
    check("continuous boundary gain", abs(SpatialModel.gain(at: SpatialPoint(x: radius + 1e-7), radius: radius) - 1) < 1e-6)
}
near("distance curve extends beyond coordinate cube", SpatialModel.gain(at: SpatialPoint(x: 100), radius: 1), 0.01)
check("nonfinite coordinates normalized", SpatialPoint(x: .nan, y: .infinity, z: -.infinity).bounded == .zero)
check("coordinate bounds", SpatialPoint(x: 99, y: -80, z: 12).bounded == SpatialPoint(x: 50, y: -50, z: 12))
near("radius cannot be zero", SpatialModel.radius(0), 0.25)
for axis in SpatialAxis.allCases { for sign in [-1.0, 1] {
    let start = SpatialPoint(x: 2, y: 3, z: 4)
    let move = SpatialThrow(start: start, axis: axis, sign: sign, distance: 10, speed: 5)
    near("throw duration", move.duration, 2)
    check("throw starts at current point", move.position(at: 0) == start)
    near("throw half way", move.position(at: 1)[axis], start[axis] + sign * 5)
    near("throw exact end", move.position(at: 3)[axis], start[axis] + sign * 10)
    for held in SpatialAxis.allCases where held != axis { near("throw preserves orthogonal coordinate", move.position(at: 1)[held], start[held]) }
} }
let clippedThrow = SpatialThrow(start: SpatialPoint(x: 49), axis: .x, sign: 1, distance: 10, speed: 5)
near("clipped duration uses actual travel", clippedThrow.duration, 0.2)
near("throw stops at boundary", clippedThrow.position(at: 100).x, 50)
let blockedThrow = SpatialThrow(start: SpatialPoint(x: 50), axis: .x, sign: 1, distance: 10, speed: 5)
near("outward boundary throw duration zero", blockedThrow.duration, 0)
check("zero-duration result finite", blockedThrow.position(at: 0) == SpatialPoint(x: 50))
let invalidThrow = SpatialThrow(start: .zero, axis: .x, sign: 1, distance: .nan, speed: 0)
check("invalid travel cannot create motion", invalidThrow.duration == 0 && invalidThrow.end == .zero)

// Clear words retains actual speech-band information; it is not low-band encoding.
let claritySource = DSP.sum(DSP.tone(200, amplitude: 0.1, sampleRate: 32768, count: 32768), DSP.tone(6000, amplitude: 0.1, sampleRate: 32768, count: 32768))
let clarityBypass = ClearSpeechMix(speech: claritySource, speechRate: 32768, carrier: 19.75, definition: 0, carrierLevel: 0)
check("definition and underlay bypass exactly preserves voice", clarityBypass.samples == claritySource)
near("clear speech keeps source sample rate", clarityBypass.sampleRate, 32768)
let clarity = ClearSpeechMix(speech: claritySource, speechRate: 32768, carrier: 19.75, definition: 1, carrierLevel: 0)
let claritySpectrum = DSP.spectrum(Array(clarity.samples.suffix(16384)), sampleRate: 32768)
let lowPresence = amplitude(claritySpectrum, 200)
let highPresence = amplitude(claritySpectrum, 6000)
check("definition lifts articulation relative to vocal body", highPresence / lowPresence > 1.4)
check("definition preserves low vocal content", lowPresence >= 0.099 && lowPresence < 0.11)
check("speech above carrier simulation Nyquist remains present", highPresence > 0.14)
for definition in [0.0, 0.5, 1] { for bed in [0.0, 0.06, 0.25] {
    let mix = ClearSpeechMix(speech: claritySource.map { $0 * 10 }, speechRate: 32768, carrier: 140.67, definition: definition, carrierLevel: bed)
    check("clear mix retains duration", mix.samples.count == claritySource.count)
    check("voice reserves peak headroom", mix.voice.allSatisfy { abs($0) <= 0.85000001 })
    check("mix cannot clip", mix.samples.allSatisfy { $0.isFinite && abs($0) <= 0.88750001 })
} }
let clearSilence = ClearSpeechMix(speech: Array(repeating: 0, count: 10001), speechRate: 22050, carrier: 19.75)
check("clear mix keeps exact odd-length sample count", clearSilence.samples.count == 10001)
check("clear mix does not fill silence", clearSilence.samples.allSatisfy { $0 == 0 })
let clearEmpty = ClearSpeechMix(speech: [], speechRate: 22050, carrier: 140)
check("empty clear mix", clearEmpty.samples.isEmpty && clearEmpty.voice.isEmpty)
let quietSpeech = DSP.tone(180, amplitude: 0.001, sampleRate: 22050, count: 22050)
let quietMix = ClearSpeechMix(speech: quietSpeech, speechRate: 22050, carrier: 140, definition: 0, carrierLevel: 0)
check("clear mode does not normalize quiet voice upward", quietMix.samples == quietSpeech)
let onlyVoice = ClearSpeechMix(speech: claritySource, speechRate: 32768, carrier: 256, intonationDepth: 0, definition: 0, carrierLevel: 0)
let underlayMix = ClearSpeechMix(speech: claritySource, speechRate: 32768, carrier: 256, intonationDepth: 0, definition: 0, carrierLevel: 0.1)
let expectedUnderlay = SubVocalSimulation(speech: claritySource, speechRate: 32768, carrier: 256, outputRate: 32768)
let mixError = underlayMix.samples.indices.map { abs(underlayMix.samples[$0] - (0.9 * onlyVoice.samples[$0] + 0.1 * expectedUnderlay.modulated[$0])) }.max() ?? 1
near("carrier is a separate gain-controlled underlay", mixError, 0)

// Room placement, Euler orientation and directional source model.
let identityOrientation = SourceOrientation()
check("identity rotation", identityOrientation.rotate(SpatialPoint(x: 1, y: 2, z: 3)) == SpatialPoint(x: 1, y: 2, z: 3))
near("positive yaw turns forward left", SourceOrientation(yaw: 90).forward.x, -1)
near("positive pitch tilts forward upward", SourceOrientation(pitch: 90).forward.y, 1)
near("positive roll rotates local right upward", SourceOrientation(roll: 90).rotate(SpatialPoint(x: 1)).y, 1)
for yaw in [-180.0, -35, 0, 90] { for pitch in [-90.0, 0, 45] { for roll in [-120.0, 0, 90] {
    let o = SourceOrientation(yaw: yaw, pitch: pitch, roll: roll)
    near("rotation preserves vector length", o.rotate(SpatialPoint(x: 3, y: 4, z: 12)).distance, 13)
    near("forward is a unit vector", o.forward.distance, 1)
    let noRoll = SourceOrientation(yaw: yaw, pitch: pitch)
    near("axially symmetric gain ignores roll", o.gainTowardOrigin(from: SpatialPoint(x: 2, y: 3, z: -4), directional: true), noRoll.gainTowardOrigin(from: SpatialPoint(x: 2, y: 3, z: -4), directional: true))
} } }
for p in [SpatialPoint(x: 2), SpatialPoint(x: -2), SpatialPoint(y: 2), SpatialPoint(y: -2), SpatialPoint(z: 2), SpatialPoint(z: -2), SpatialPoint(x: 3, y: 4, z: -5)] {
    let o = SourceOrientation.facingOrigin(from: p)
    near("face listener maximizes directional gain", o.gainTowardOrigin(from: p, directional: true), 1)
    near("point source ignores orientation", o.gainTowardOrigin(from: p, directional: false), 1)
}
near("directional rear gain", SourceOrientation().gainTowardOrigin(from: SpatialPoint(z: -2), directional: true), 0.25)
near("directional side gain", SourceOrientation().gainTowardOrigin(from: SpatialPoint(x: 2), directional: true), 0.625)
near("coincident source remains finite", SourceOrientation().gainTowardOrigin(from: .zero, directional: true), 1)
let roomModel = VirtualRoom()
check("synthetic cloud deterministic", roomModel.pointCloud == roomModel.pointCloud)
check("synthetic cloud bounded count", roomModel.pointCloud.count == 1074)
check("room has eight corners", roomModel.corners.count == 8)
check("listener inside room", roomModel.contains(.zero))
check("outside source detected", !roomModel.contains(SpatialPoint(x: 5)))
check("cloud on modeled surfaces", roomModel.pointCloud.allSatisfy { p in
    roomModel.contains(p) && (abs(abs(p.x) - roomModel.width / 2) < 1e-9 || abs(abs(p.z) - roomModel.depth / 2) < 1e-9 || abs(p.y - roomModel.floorY) < 1e-9 || abs(p.y - roomModel.ceilingY) < 1e-9)
})
let invalidRoom = VirtualRoom(width: .nan, depth: 100, height: -1)
check("room dimensions finite and bounded", invalidRoom.width == 8 && invalidRoom.depth == 30 && invalidRoom.height == 2)
for yaw in [0.0, 35, 90, 180, 270] { for elevation in [10.0, 30, 80] {
    let p = SpatialPoint(x: 2, y: 0.4, z: -3)
    let uv = RoomProjection.project(p, yaw: yaw, elevation: elevation)
    let q = RoomProjection.unproject(u: uv.u, v: uv.v, height: p.y, yaw: yaw, elevation: elevation)
    near("room placement roundtrip x", q.x, p.x)
    near("room placement preserves height", q.y, p.y)
    near("room placement roundtrip z", q.z, p.z)
} }

print("\(checks - failures)/\(checks) deterministic checks passed.")
exit(failures == 0 ? 0 : 1)
