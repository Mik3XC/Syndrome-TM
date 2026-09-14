// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

struct StudioNote: View {
    let title: String
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(.green)
            Text(text).font(.callout).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AudioControls: View {
    @ObservedObject var audio: StudioAudio
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Toggle("Enable audible previews", isOn: $audio.audibleEnabled).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview level · \(Int(audio.volume * 100))%").font(.caption.monospacedDigit())
                    Slider(value: $audio.volume, in: 0...0.4, step: 0.01) { Text("Preview level") }.labelsHidden()
                }.frame(maxWidth: 220)
                Spacer()
                Button("Stop audio", systemImage: "stop.fill") { audio.stop() }.disabled(!audio.isPlaying)
            }
            Text(audio.status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("audioStatus")
            Text("Audible previews use the current macOS output device. Syndrome does not choose, discover, or pair Bluetooth devices.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct SoundBoardView: View {
    @ObservedObject var audio: StudioAudio
    let masterFrequency: Double
    let playing: Bool
    let started: Date
    let frozen: Double
    @State private var preset: SoundPreset = .sine
    private let rate = 8192.0
    private func detail(_ item: SoundPreset) -> String { item == .sine ? "\(masterFrequency.formatted(.number.precision(.fractionLength(2)))) Hz · master tone" : item.detail }
    var body: some View {
        let duration = preset == .sine ? 8.0 : 2.0
        let samples = preset.samples(sampleRate: rate, duration: duration, frequency: masterFrequency)
        let timeEnd = preset == .sine ? MasterFrequency.timeSpanMS(masterFrequency) : 100.0
        VStack(alignment: .leading, spacing: 20) {
            AudioControls(audio: audio)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SoundPreset.allCases, id: \.self) { item in
                    Button { preset = item; audio.stop() } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item == .sweep ? "arrow.up.right" : "waveform").font(.title2).frame(width: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.rawValue).font(.headline)
                                Text(detail(item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: item == preset ? "checkmark.circle.fill" : "circle").foregroundStyle(item == preset ? .green : .secondary)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .background(preset == item ? .green.opacity(0.12) : .secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(preset == item ? .green.opacity(0.6) : .secondary.opacity(0.2)))
                        .accessibilityAddTraits(preset == item ? .isSelected : [])
                }
            }
            HStack {
                Button("Play audible pad · 2 seconds", systemImage: "play.fill") {
                    audio.play(preset.samples(sampleRate: 44100, frequency: masterFrequency), sampleRate: 44100, label: preset.rawValue)
                }.buttonStyle(.borderedProminent).tint(.green).disabled(!audio.audibleEnabled)
                Text("\(preset.rawValue) selected · no autoplay").font(.caption).foregroundStyle(.secondary)
            }
            SpatialControlView(audio: audio, space: audio.space, visualsPlaying: playing, canPlay: audio.audibleEnabled,
                               playLabel: "Play selected pad · 2 s") {
                audio.play(preset.samples(sampleRate: 44100, frequency: masterFrequency), sampleRate: 44100, label: preset.rawValue)
            }
            HStack(alignment: .top, spacing: 16) {
                Plot(title: "Selected pad · time", traces: [timeTrace(preset.rawValue, samples, rate: rate, color: .green)], xRange: 0...timeEnd, yRange: -1.05...1.05, xLabel: "Time (ms)", summary: "\(detail(preset)). Time axis 0 to \(timeEnd) milliseconds, amplitude between minus one and one.", playing: playing, start: started, frozen: frozen)
                Plot(title: "Selected pad · spectrum", traces: [spectrumTrace("\(Int(duration))-second observation", samples, rate: rate, window: .hann, color: .green)], xRange: 0...(preset == .sine ? max(5, masterFrequency * 1.5) : 1200), yRange: 0...1.05, xLabel: "Frequency (Hz)", yLabel: "One-sided peak amplitude", summary: "\(detail(preset)). Hann FFT, 8192 hertz sample rate, \(samples.count) samples, \(1 / duration) hertz bin spacing.", isSpectrum: true)
            }
            StudioNote(title: "A sound board you can inspect", text: "Pads are synthesized locally. Selecting a pad updates the plots; Play sends a two-second audible preview only when enabled. All pads have short fades. Decay, fades, and a sweep spread energy across frequency bins, so these spectra are not all isolated lines. The Pure tone pad follows the master frequency; the other pads keep their labeled frequencies. Pure-tone plots use eight seconds for low-frequency detail; playback lasts two seconds. Low frequencies may not be audible or reproduced by the selected device. The SubVocal and Range screens also offer explicit simulation playback.")
        }
    }
}

struct SpeechLabView: View {
    @ObservedObject var audio: StudioAudio
    @Binding var text: String
    @State private var useIntonation = true
    @State private var intonationDepth = 1.0
    private var activeDepth: Double { useIntonation ? intonationDepth : 0 }
    let carrierFrequency: Double
    private var carrierLabel: String { carrierFrequency.formatted(.number.precision(.fractionLength(2))) + " Hz" }
    let playing: Bool
    let started: Date
    let frozen: Double
    private var stale: Bool { audio.renderedText != text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StudioNote(title: "Words first", text: "Clear words keeps the actual voice, adds a gentle articulation lift, and places the \(carrierLabel) carrier quietly underneath. The words use the ordinary audible speech band; the master sets only the underlay frequency. Carrier only preserves cadence and intonation without the speech detail needed for words. Generate prepares the previews silently; both modes use the shared spatial sphere.")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Type your message").font(.headline)
                    Spacer()
                    Text("\(text.count)/300 characters").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                TextEditor(text: $text).font(.body).frame(height: 110).padding(8)
                    .scrollContentBackground(.hidden).background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("Text to speech message")
                    .onChange(of: text) { _, value in if value.count > 300 { text = String(value.prefix(300)) }; audio.stop() }
                HStack {
                    Button(audio.rendering ? "Rendering locally…" : "Generate preview", systemImage: "waveform.path") { audio.renderSpeech(text) }
                        .buttonStyle(.borderedProminent).tint(.green).disabled(audio.rendering || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if audio.rendering { Button("Cancel") { audio.cancelRender() } }
                    Button("Play audible speech", systemImage: "speaker.wave.2.fill") {
                        audio.play(audio.speechSamples, sampleRate: audio.speechRate, label: "ordinary speech")
                    }.disabled(!audio.audibleEnabled || audio.speechSamples.isEmpty || stale || audio.rendering)
                    Button(audio.clearWords ? "Play clear words" : "Play carrier simulation", systemImage: "waveform") {
                        audio.playSpeechPreview(frequency: carrierFrequency, intonationDepth: activeDepth)
                    }.buttonStyle(.borderedProminent).tint(.green)
                        .disabled(!audio.audibleEnabled || audio.speechSamples.isEmpty || stale || audio.rendering)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Picker("Speech output", selection: $audio.clearWords) {
                    Text("Clear words + carrier").tag(true)
                    Text("Carrier only").tag(false)
                }.pickerStyle(.segmented)
                if audio.clearWords {
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Word definition · \(Int(audio.wordDefinition * 100))%").font(.caption.monospacedDigit())
                            Slider(value: $audio.wordDefinition, in: 0...1, step: 0.05) { Text("Word definition") }.labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Carrier underlay · \(Int((audio.speechCarrierLevel * 100).rounded()))%").font(.caption.monospacedDigit())
                            Slider(value: $audio.speechCarrierLevel, in: 0...0.25, step: 0.01) { Text("Carrier underlay") }.labelsHidden()
                        }
                    }
                    Text("For clearer words, keep the underlay low. Definition gently lifts articulation frequencies; it does not confine speech to the carrier range. Set both controls to zero for the original voice with peak headroom. Play audible speech provides the unprocessed comparison. Distance attenuation still applies; Centre returns the sphere to unity distance gain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Carrier modulation", selection: $useIntonation) {
                    Text("Cadence only").tag(false)
                    Text("Cadence + intonation").tag(true)
                }.pickerStyle(.segmented)
                HStack(spacing: 16) {
                    Text("Intonation strength · \(Int(intonationDepth * 100))%").font(.caption.monospacedDigit()).frame(width: 190, alignment: .leading)
                    Slider(value: $intonationDepth, in: 0...1, step: 0.05) { Text("Intonation strength") }.labelsHidden().disabled(!useIntonation)
                }
                Text("Master frequency is the centre tone. Cadence shapes amplitude; intonation bends frequency. The actual tone can move below and above the master setting. Change a setting, then press Play again to compare.")
                    .font(.caption).foregroundStyle(.secondary)
                if let track = audio.pitchTrack {
                    Text("Estimated voiced frames: \(Int(track.voicedFraction * 100))% · \(track.medianFrequency.map { "median vocal pitch " + String(format: "%.0f Hz", $0) } ?? "no reliable vocal pitch found; cadence-only fallback")")
                        .font(.caption).foregroundStyle(track.medianFrequency == nil ? .orange : .secondary)
                }
            }.padding(16).background(.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: useIntonation) { _, _ in audio.stop() }
            .onChange(of: intonationDepth) { _, _ in audio.stop() }
            AudioControls(audio: audio)
            SpatialControlView(audio: audio, space: audio.space, visualsPlaying: playing,
                               canPlay: audio.audibleEnabled && !audio.speechSamples.isEmpty && !stale && !audio.rendering,
                               playLabel: audio.clearWords ? "Play clear words in space" : "Play carrier in space") {
                audio.playSpeechPreview(frequency: carrierFrequency, intonationDepth: activeDepth)
            }
            if !audio.speechSamples.isEmpty {
                if stale { Label("Text changed. Generate again to update the preview.", systemImage: "arrow.clockwise").font(.callout).foregroundStyle(.orange) }
                if audio.clearWords { clarityPlots }
                speechPlots
            } else {
                VStack(spacing: 12) {
                    AlienLogo().frame(width: 64, height: 64)
                    Text("Your signal begins with a sentence.").font(.headline)
                    Text("Generate a preview to compare actual speech with the carrier simulation, then choose which one to play.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(36).background(.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            StudioNote(title: "What \(carrierLabel) means here", text: "We calculate a 30 ms RMS amplitude envelope from the generated speech, normalize it, and use it to shape the carrier amplitude. Cadence only keeps a fixed tone. Cadence + intonation estimates relative vocal pitch and changes the tone frequency with continuous phase. This keeps rhythm and an estimated pitch contour, not the phonetic detail needed to reproduce the words. The pitch tracker assumes 60–500 Hz periodic voice; unvoiced consonants and low-confidence frames return toward the centre tone. Estimates can contain octave errors. Relative pitch is limited to ±12 semitones, smoothed over 25 ms, and kept below 45% of the simulation sample rate. Modulating a carrier adds sidebands, so this result is not confined to a single frequency or a fixed narrow band. Play carrier simulation sends this modeled waveform to the current audio output, with 20 ms edge fades. Its playback follows the Audio toggle and preview level; the plot itself does not start playback.")
        }
    }

    private var clarityPlots: some View {
        let mix = ClearSpeechMix(speech: audio.speechSamples, speechRate: audio.speechRate, carrier: carrierFrequency,
                                 pitchTrack: audio.pitchTrack, intonationDepth: activeDepth,
                                 definition: audio.wordDefinition, carrierLevel: audio.speechCarrierLevel)
        let end = max(0.1, Double(mix.samples.count) / mix.sampleRate)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                Plot(title: "Before · original voice", traces: [overviewTrace("Original speech", samples: audio.speechSamples, rate: audio.speechRate, color: .blue)], xRange: 0...end, yRange: -1...1, xLabel: "Time (seconds)", summary: "Original voice at its native sample rate, before definition and carrier mixing.")
                Plot(title: "After · clear words + carrier", traces: [overviewTrace("Clear words mix", samples: mix.samples, rate: mix.sampleRate, color: .green)], xRange: 0...end, yRange: -1...1, xLabel: "Time (seconds)", summary: "Actual clear-words mix before 5 millisecond edge fades, spatial filtering and distance gain. Original speech duration and sample rate retained. Audible speech bandwidth.")
            }
            Text("Clear words retains the voice’s original \(Int(mix.sampleRate)) Hz sample rate and timing. Definition adds up to about 4 dB of high-frequency presence, then reserves peak headroom without boosting quiet clips. The carrier remains a separate underlay; the carrier-only plots below do not describe the full clear-words spectrum.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var speechPlots: some View {
        let samples = audio.speechSamples
        let duration = Double(samples.count) / audio.speechRate
        let simulation = SubVocalSimulation(speech: samples, speechRate: audio.speechRate, carrier: carrierFrequency, pitchTrack: audio.pitchTrack, intonationDepth: activeDepth)
        let end = max(0.1, duration)
        let fftSize = 65536
        let fftInput = Array(simulation.modulated.prefix(fftSize)) + Array(repeating: 0.0, count: max(0, fftSize - simulation.modulated.count))
        let spectrum = DSP.spectrum(fftInput, sampleRate: simulation.sampleRate)
        let maximum = spectrum.amplitudes.max() ?? 1
        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Plot(title: "Actual synthesized speech", traces: [overviewTrace("Ordinary speech", samples: samples, rate: audio.speechRate, color: .blue)], xRange: 0...end, yRange: -1...1, xLabel: "Time (seconds)", summary: "Actual locally synthesized speech for the message: \(audio.renderedText). Duration \(String(format: "%.1f", duration)) seconds. These are the samples used for the audible preview.", playing: playing, start: started, frozen: frozen)
                Plot(title: "\(carrierLabel) · carrier simulation", traces: [overviewTrace(useIntonation ? "Cadence + intonation" : "Cadence only", samples: simulation.modulated, rate: simulation.sampleRate, color: .green), overviewTrace("RMS envelope", samples: simulation.envelope, rate: simulation.sampleRate, color: .orange, dashed: true)], xRange: 0...end, yRange: -1...1, xLabel: "Time (seconds)", summary: "\(carrierLabel) centre carrier shaped by normalized speech amplitude and \(useIntonation ? "estimated intonation" : "fixed pitch"). This does not encode intelligible words.", playing: playing, start: started, frozen: frozen)
            }
            if let track = audio.pitchTrack {
                HStack(alignment: .top, spacing: 16) {
                    Plot(title: "Estimated vocal pitch", traces: [Trace(name: "Voiced frames only", x: track.frames.map(\.time), y: track.frames.map { $0.frequency ?? .nan }, color: .blue)], xRange: 0...end, yRange: 0...550, xLabel: "Time (seconds)", yLabel: "Estimated voice frequency (Hz)", summary: "Pitch estimate in 60 to 500 hertz. Gaps indicate no reliable periodicity. \(Int(track.voicedFraction * 100)) percent of frames are voiced.")
                    Plot(title: "Mapped carrier frequency", traces: [overviewTrace("Tone contour", samples: simulation.instantaneousFrequencies, rate: simulation.sampleRate, color: .green), Trace(name: "Master centre", x: [0, end], y: [carrierFrequency, carrierFrequency], color: .orange, dashed: true)], xRange: 0...end, yRange: 0...max(1, (simulation.instantaneousFrequencies.max() ?? carrierFrequency) * 1.15), xLabel: "Time (seconds)", yLabel: "Instantaneous tone frequency (Hz)", summary: "Carrier frequency varies from \(String(format: "%.2f", simulation.instantaneousFrequencies.min() ?? carrierFrequency)) to \(String(format: "%.2f", simulation.instantaneousFrequencies.max() ?? carrierFrequency)) hertz. Master centre \(carrierLabel).")
                }
            }
            Plot(title: "Carrier simulation · spectral shape", traces: [Trace(name: "Relative to largest bin", x: spectrum.frequencies, y: spectrum.amplitudes.map { maximum > 0 ? $0 / maximum : 0 }, color: .green)], xRange: 0...min(4096, max(100, (simulation.instantaneousFrequencies.max() ?? carrierFrequency) * 1.5)), yRange: 0...1.05, xLabel: "Frequency (Hz)", yLabel: "Relative spectral magnitude · max = 1", summary: "Carrier \(carrierLabel) plus sidebands introduced by the changing envelope. Relative spectral magnitude, not calibrated amplitude.", isSpectrum: true, marker: carrierFrequency)
            Text("Spectrum uses the first 8 seconds, or zero-padding for shorter phrases. FFT bin spacing is 0.125 Hz; padding does not improve true resolution. Dashed spectral line marks the master centre, not the full frequency excursion. Waveform overviews retain the minimum and maximum in each display block.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private func overviewTrace(_ name: String, samples: [Double], rate: Double, color: Color, dashed: Bool = false) -> Trace {
    let block = max(1, samples.count / 1000)
    var x: [Double] = [], y: [Double] = []
    for start in stride(from: 0, to: samples.count, by: block) {
        let end = min(start + block, samples.count)
        let low = (start..<end).min(by: { samples[$0] < samples[$1] })!
        let high = (start..<end).max(by: { samples[$0] < samples[$1] })!
        for i in [low, high].sorted() { x.append(Double(i) / rate); y.append(samples[i]) }
    }
    return Trace(name: name, x: x, y: y, color: color, dashed: dashed)
}

struct RangeLabView: View {
    @ObservedObject var audio: StudioAudio
    let carrierFrequency: Double
    private var carrierLabel: String { carrierFrequency.formatted(.number.precision(.fractionLength(2))) + " Hz" }
    @State private var distance = 5.0
    @State private var excessLoss = 0.0
    var body: some View {
        let gain = RangeModel.gain(distance: distance, excessLossDBPerMetre: excessLoss)
        let distances = (0...396).map { 1 + Double($0) / 4 }
        let levels = distances.map { RangeModel.levelChangeDB(distance: $0, excessLossDBPerMetre: excessLoss) }
        let rate = 8192.0
        let timeEnd = MasterFrequency.timeSpanMS(carrierFrequency)
        let count = Int(ceil(timeEnd * rate / 1000)) + 1
        let source = DSP.tone(carrierFrequency, sampleRate: rate, count: count)
        let received = DSP.tone(carrierFrequency, amplitude: gain, sampleRate: rate, count: count, phase: -2 * .pi * carrierFrequency * RangeModel.delay(distance: distance))
        VStack(alignment: .leading, spacing: 20) {
            StudioNote(title: "Idealized range simulation", text: "A point-source, free-field model illustrates how pressure amplitude changes with distance. The reference is an assumed amplitude of 1 at one metre. This is not a measured range, audibility estimate, Bluetooth range, or prediction of \(carrierLabel) performance from your hardware. Frequency changes the waveform and phase; this idealized attenuation law itself is frequency-independent.")
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Distance · \(distance.formatted(.number.precision(.fractionLength(1)))) m").font(.headline)
                    Slider(value: $distance, in: 1...100, step: 0.5) { Text("Distance in metres") }.labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("Assumed excess loss · \(excessLoss.formatted(.number.precision(.fractionLength(2)))) dB/m").font(.headline)
                    Slider(value: $excessLoss, in: 0...0.5, step: 0.01) { Text("Excess loss in decibels per metre") }.labelsHidden()
                }
            }.padding(18).background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 24) {
                rangeMetric("Pressure ratio", String(format: "%.4f ×", gain))
                rangeMetric("Level relative to 1 m", String(format: "%.2f dB", RangeModel.levelChangeDB(distance: distance, excessLossDBPerMetre: excessLoss)))
                rangeMetric("Propagation time", String(format: "%.1f ms", RangeModel.delay(distance: distance) * 1000))
            }
            HStack {
                Button("Play reference · 2s", systemImage: "play.fill") {
                    audio.playRange(frequency: carrierFrequency, distance: nil, excessLoss: excessLoss)
                }.disabled(!audio.audibleEnabled)
                Button("Play at distance · 2s", systemImage: "waveform") {
                    audio.playRange(frequency: carrierFrequency, distance: distance, excessLoss: excessLoss)
                }.disabled(!audio.audibleEnabled)
                Text("Uses the master Audio toggle and level. Attenuation is retained.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                Plot(title: "Reference · normalized source", traces: [timeTrace(carrierLabel, source, rate: rate, color: .blue)], xRange: 0...timeEnd, yRange: -1.05...1.05, xLabel: "Time (ms)", summary: "Reference amplitude one at one metre. Ideal \(carrierLabel) tone.")
                Plot(title: "At the selected distance", traces: [timeTrace("Attenuated + delayed", received, rate: rate, color: .green)], xRange: 0...timeEnd, yRange: -1.05...1.05, xLabel: "Time (ms)", summary: "\(distance) metres, amplitude ratio \(gain), delay \(RangeModel.delay(distance: distance)) seconds. Same amplitude axis as reference.")
            }
            Plot(title: "Level change with distance", traces: [Trace(name: "Assumed free-field model", x: distances, y: levels, color: .green)], xRange: 1...100, yRange: -90...0, xLabel: "Distance (m)", yLabel: "Relative pressure level (dB)", summary: "Inverse-distance pressure decay with \(excessLoss) decibels per metre excess loss. Selected distance \(distance) metres.", marker: distance)
            StudioNote(title: "Assumptions you can see", text: "Pressure ratio = (1/r) × 10^[−a(r−1)/20], where r is metres and a is the assumed excess loss in dB/m. Intensity follows 1/r² when a = 0. Propagation uses an assumed sound speed of 343 m/s. The reference waveform uses emission time; the received waveform uses arrival time delayed by r/343. Room reflections, obstacles, noise, source directivity and transducer response are excluded. No maximum intelligible range is inferred.")
        }
        .onChange(of: distance) { _, _ in audio.stop() }
        .onChange(of: excessLoss) { _, _ in audio.stop() }
    }
    private func rangeMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit().bold()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BluetoothPrepView: View {
    @AppStorage("preparedBluetoothDeviceLabel") private var deviceName = ""
    @AppStorage("preparedBluetoothProfile") private var profile = "Audio output"
    @AppStorage("bluetoothPlanSaved") private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 34)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Disconnected by design").font(.title2.bold())
                    Text("Preparation only · no scan · no pairing · no connection").foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                Text("Local pairing plan").font(.headline)
                TextField("Device label (optional)", text: $deviceName).textFieldStyle(.roundedBorder)
                    .onChange(of: deviceName) { _, _ in saved = false }
                Picker("Intended use", selection: $profile) {
                    Text("Audio output").tag("Audio output")
                    Text("Future control accessory").tag("Future control accessory")
                }.onChange(of: profile) { _, _ in saved = false }
                HStack {
                    Button("Save preparation locally", systemImage: "square.and.arrow.down") { saved = true }
                    if saved { Label("Plan saved on this Mac", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                Text("Only this label and intended use are stored in local app preferences. Device names entered here are not discovered or verified.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14))
            StudioNote(title: "Prepared integration boundary", text: "An audio output device would be paired and routed through macOS. A future control accessory would require a separately implemented protocol and explicit connection controls. Neither path is connected here; there is no Bluetooth manager, permission request, scan, advertisement, or transmission.")
            HStack {
                Button("Scan (not implemented)") {}.disabled(true)
                Button("Pair (not implemented)") {}.disabled(true)
                Button("Connect (not implemented)") {}.disabled(true)
            }
            StudioNote(title: "When connection work is requested", text: "The next implementation step is to choose the actual accessory and protocol, then add user-controlled connection state and error handling. This preparation screen makes no claim about compatibility or range.")
        }
    }
}

struct MasterFrequencyControl: View {
    @Binding var frequency: Double
    @ObservedObject var audio: StudioAudio
    @State private var entry = ""
    @State private var error: String?
    private var formatted: String { String(format: "%.2f", frequency) }
    private var sliderPosition: Binding<Double> {
        Binding(get: { MasterFrequency.position(frequency) }, set: { frequency = MasterFrequency.frequency(at: $0) })
    }
    private var preset: Binding<Double> {
        Binding(get: { MasterFrequency.presets.contains(frequency) ? frequency : -1 }, set: { if $0 > 0 { frequency = $0 } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MASTER FREQUENCY").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                    Text("\(formatted) Hz").font(.title3.monospacedDigit().bold()).foregroundStyle(.green)
                }.frame(minWidth: 110, alignment: .leading)
                Picker("Frequency preset", selection: preset) {
                    Text("Custom frequency").tag(-1.0)
                    ForEach(MasterFrequency.presets, id: \.self) { value in
                        Text("\(value.formatted(.number.precision(.fractionLength(0...2)))) Hz").tag(value)
                    }
                }.labelsHidden().frame(width: 115).accessibilityIdentifier("masterFrequencyPreset")
                TextField("Hz", text: $entry).textFieldStyle(.roundedBorder).frame(width: 68)
                    .accessibilityLabel("Exact master frequency in hertz")
                    .onSubmit(applyEntry)
                Button("Set", action: applyEntry)
                Stepper("Adjust master frequency by 0.01 Hz", value: $frequency, in: MasterFrequency.limits, step: 0.01)
                    .labelsHidden().accessibilityValue("\(formatted) Hz")
                Spacer(minLength: 0)
                Button("Test tone · 2s", systemImage: "play.fill") {
                    audio.play(SoundPreset.sine.samples(sampleRate: 44100, frequency: frequency), sampleRate: 44100, label: "\(formatted) Hz test tone · 2 seconds")
                }.disabled(!audio.audibleEnabled)
                Button { frequency = SubVocalSimulation.defaultCarrier } label: { Image(systemName: "arrow.counterclockwise") }
                    .help("Reset master frequency to 19.75 Hz").accessibilityLabel("Reset master frequency to 19.75 hertz")
            }
            HStack(spacing: 10) {
                Text("0.50 Hz").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Slider(value: sliderPosition, in: 0...1) { Text("Master frequency, logarithmic scale") }.labelsHidden()
                    .accessibilityValue("\(formatted) Hz").accessibilityIdentifier("masterFrequencySlider")
                Text("2,000 Hz").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Divider().frame(height: 18)
                Toggle("Audio", isOn: $audio.audibleEnabled).toggleStyle(.switch).fixedSize()
                    .accessibilityLabel("Enable audible previews")
                Slider(value: $audio.volume, in: 0...0.4, step: 0.01) { Text("Master preview level") }.labelsHidden().frame(width: 70)
                    .accessibilityValue("\(Int(audio.volume * 100)) percent")
                Text("\(Int(audio.volume * 100))%").font(.caption.monospacedDigit()).frame(width: 28)
                Button { audio.stop() } label: { Image(systemName: "stop.fill") }
                    .disabled(!audio.isPlaying).accessibilityLabel("Stop audio").help("Stop audio")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Controls Pure tone, SubVocal carrier, and Range. Other pads and lessons retain their own frequencies. Test tones use the shared Audio toggle and level; changing frequency stops playback. Audibility depends on the device, listener, and level.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { entry = formatted }
        .onChange(of: frequency) { _, _ in entry = formatted; error = nil }
    }
    private func applyEntry() {
        let normalizedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalizedEntry), value.isFinite, MasterFrequency.limits.contains(value) else {
            error = "Enter a frequency from 0.50 to 2,000 Hz. The previous setting is unchanged."
            return
        }
        frequency = MasterFrequency.normalized(value)
        entry = formatted
        error = nil
    }
}
