// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

@main
struct SyndromeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Syndrome™") {
            LabView().frame(minWidth: 1000, minHeight: 720)
        }.defaultSize(width: 1240, height: 920)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum Lesson: String, CaseIterable, Identifiable {
    case soundboard = "Sound Board", speech = "SubVocal Speech", range = "Range", bluetooth = "Bluetooth Prep"
    case waveforms = "Waveforms", modulation = "Modulation", beats = "Beats", recording = "Recording"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .soundboard: return "square.grid.2x2.fill"
        case .speech: return "text.bubble"
        case .range: return "point.3.connected.trianglepath.dotted"
        case .bluetooth: return "antenna.radiowaves.left.and.right.slash"
        case .waveforms: return "waveform.path"
        case .modulation: return "arrow.left.arrow.right"
        case .beats: return "waveform.path.ecg"
        case .recording: return "line.3.horizontal.decrease.circle"
        }
    }
    var subtitle: String {
        switch self {
        case .soundboard: return "Select a sound. Inspect the signal. Preview on your terms."
        case .speech: return "Text to SubVocal Speech · hear the voice or the carrier simulation."
        case .range: return "Explore distance with explicit assumptions."
        case .bluetooth: return "Prepare the next connection. Stay disconnected."
        case .waveforms: return "One signal. Two ways to see it."
        case .modulation: return "Move the spectrum. Keep the information in view."
        case .beats: return "An envelope is a pattern, not an extra tone."
        case .recording: return "Separate filtering, sampling, and observation length."
        }
    }
}

struct LabView: View {
    @State private var lesson: Lesson = .soundboard
    @StateObject private var audio = StudioAudio()
    @AppStorage("masterFrequencyHz") private var masterFrequency = 19.75
    @State private var resetToken = UUID()
    @State private var speechText = "Hello from Syndrome. Explore the signal, understand the sound."
    @Environment(\.scenePhase) private var scenePhase
    @State private var frequency = 64.0
    @State private var amplitude = 0.8
    @State private var messageFrequency = 60.0
    @State private var carrier = 400.0
    @State private var depth = 0.8
    @State private var difference = 8.0
    @State private var nonlinearStrength = 0.5
    @State private var cutoff = 60.0
    @State private var sampleRate = 1024.0
    @State private var fftCount = 1024
    @State private var window: FFTWindow = .hann
    @State private var playing = true
    @State private var started = Date()
    @State private var frozen = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rate = 2048.0
    private let count = 2048

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    AlienLogo().frame(width: 38, height: 38)
                    Text("Syndrome™").font(.title2.bold())
                }.padding(.top, 22)
                Text("SOUND / SIGNAL / SPACE").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    ForEach(Array(Lesson.allCases.enumerated()), id: \.element) { index, item in
                        Button { lesson = item } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol).frame(width: 20)
                                Text(item.rawValue).fontWeight(.medium)
                                Spacer()
                                Text("0\(index + 1)").font(.caption.monospaced())
                            }.padding(12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(lesson == item ? Color.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(lesson == item ? .blue : .primary)
                        .accessibilityAddTraits(lesson == item ? .isSelected : [])
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Label(audio.isPlaying ? "Audible preview" : "Audio stopped", systemImage: audio.isPlaying ? "speaker.wave.2" : "speaker.slash").font(.callout.weight(.medium))
                    Text("Local previews & simulations.\nBluetooth stays disconnected.").font(.caption).foregroundStyle(.secondary)
                    Text("SWIFTUI + ACCELERATE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("By: Premise LLC's\nDisinformation Labs™")
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("By: Premise LLC's Disinformation Labs trademark")
                        Text("Apache License 2.0").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(22).frame(width: 246).background(.thinMaterial)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text("EXPLORE / \(lesson.rawValue.uppercased())").font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: togglePlayback) { Label(playing ? "Pause" : "Resume", systemImage: playing ? "pause.fill" : "play.fill") }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                        .help("Pause or resume the visual scan cursor and an active sphere throw. Audio continues at the held position.")
                    Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
                        .help("Restore this lesson’s settings and reset the visual cursor.")
                }.padding(.horizontal, 28).padding(.vertical, 16)
                Divider()
                MasterFrequencyControl(frequency: $masterFrequency, audio: audio)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(lesson.rawValue).font(.system(size: 32, weight: .bold, design: .rounded))
                            Text(lesson.subtitle).font(.title3).foregroundStyle(.secondary)
                        }
                        switch lesson {
                        case .soundboard: SoundBoardView(audio: audio, masterFrequency: masterFrequency, playing: playing, started: started, frozen: frozen).id(resetToken)
                        case .speech: SpeechLabView(audio: audio, text: $speechText, carrierFrequency: masterFrequency, playing: playing, started: started, frozen: frozen).id(resetToken)
                        case .range: RangeLabView(audio: audio, carrierFrequency: masterFrequency).id(resetToken)
                        case .bluetooth: BluetoothPrepView()
                        case .waveforms: waveforms
                        case .modulation: modulation
                        case .beats: beats
                        case .recording: recording
                        }
                        Text("MODEL NOTE  •  Amplitude is dimensionless, not sound pressure. The moving cursor is a visual guide, not real-time playback. All plots show local generated data. Use a Play button to hear a studio simulation, test tone, or speech. Plots never autoplay audio.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(28)
                }.id(lesson).background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onChange(of: masterFrequency) { _, value in
            audio.stop()
            let checked = MasterFrequency.normalized(value)
            if value != checked { masterFrequency = checked }
        }
        .onChange(of: lesson) { _, _ in audio.stop(); audio.cancelRender() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { audio.stop() } }
        .onAppear { masterFrequency = MasterFrequency.normalized(masterFrequency); if reduceMotion { playing = false } }
        .onChange(of: reduceMotion) { _, reduced in if reduced && playing { togglePlayback() } }
    }

    private var waveforms: some View {
        let samples = DSP.tone(frequency, amplitude: amplitude, sampleRate: rate, count: count, phase: -.pi / 2)
        return VStack(alignment: .leading, spacing: 20) {
            controls {
                slider("Frequency", value: $frequency, range: 16...256, step: 1, unit: "Hz")
                slider("Amplitude", value: $amplitude, range: 0...1, step: 0.05, unit: "relative")
            }
            HStack(alignment: .top, spacing: 16) {
                timePlot("Signal in time", traces: [timeTrace("Sine wave", samples, rate: rate)], end: 100, amplitude: 1.1,
                         summary: "Sine wave at \(Int(frequency)) hertz, peak amplitude \(amplitude). Time axis 0 to 100 milliseconds.")
                frequencyPlot("The same signal in frequency", traces: [spectrumTrace("One-sided spectrum", samples, rate: rate)], end: 512, top: 1.1,
                              summary: "One peak at \(Int(frequency)) hertz with amplitude \(amplitude), or no peak at zero amplitude. Frequency axis 0 to 512 hertz.")
            }
            explanation("READ THE TWO VIEWS", "Frequency sets the number of cycles per second. Amplitude sets the height. A pure sine wave has one positive-frequency spectral line; increasing its amplitude makes that line taller without moving it.")
            metrics([("Period", String(format: "%.2f ms", 1000 / frequency)), ("Sample rate", "2,048 Hz"), ("FFT spacing", "1 Hz · 2,048 samples")])
            explanation("ASSUMPTIONS", "An ideal sine, sampled for one second. The frequency slider uses whole hertz, so every tone lands exactly on an FFT bin with this rectangular window. The spectrum is a one-sided peak-amplitude view; negative frequencies are omitted.")
        }
    }

    private var modulation: some View {
        let signals = DSP.modulation(messageFrequency: messageFrequency, carrier: carrier, depth: depth, sampleRate: rate, count: count)
        return VStack(alignment: .leading, spacing: 20) {
            controls {
                slider("Lower message tone", value: $messageFrequency, range: 20...120, step: 1, unit: "Hz")
                slider("Carrier", value: $carrier, range: 300...600, step: 1, unit: "Hz")
                slider("Modulation depth", value: $depth, range: 0...1, step: 0.05, unit: "relative")
            }
            modulationRow("Original", values: signals.original, color: .blue, top: 2.1, summary: "Message tones at \(Int(messageFrequency)) and \(Int(messageFrequency + 40)) hertz, each amplitude 0.5.")
            modulationRow("AM · carrier + two sidebands", values: signals.am, color: .orange, top: 2.1, summary: "Carrier at \(Int(carrier)) hertz, amplitude 1. Sidebands at carrier plus and minus each message frequency, amplitude \(depth / 4) each.")
            modulationRow("SSB · upper sideband, carrier suppressed", values: signals.ssb, color: .purple, top: 2.1, summary: "Upper sideband tones at \(Int(carrier + messageFrequency)) and \(Int(carrier + messageFrequency + 40)) hertz, amplitude \(depth / 4) each.")
            explanation("TRANSLATION ≠ COMPRESSION", "The message tones are 40 Hz apart. SSB moves both up by the carrier frequency and keeps that 40 Hz spacing. Conventional AM duplicates the message around a carrier. Selecting one sideband removes that duplicate; it does not squeeze the message into a narrower copy.")
            explanation("EXACT MODEL", "m(t) = ½ cos(2πfₘt) + ½ cos(2π(fₘ + 40)t). AM = [1 + μm(t)] cos(2πf꜀t). SSB here is analytic synthesis of only AM’s upper-sideband tones, each with amplitude μ/4. AM’s outermost lines span \(Int(2 * (messageFrequency + 40))) Hz; this SSB’s lines span 40 Hz when μ > 0. For a general baseband occupying 0…B, double-sideband AM spans 2B and SSB spans B. None of these operations compress time or information bandwidth.")
        }
    }

    private var beats: some View {
        let first = DSP.tone(128, sampleRate: rate, count: count)
        let second = DSP.tone(128 + difference, sampleRate: rate, count: count)
        let linear = DSP.sum(first, second)
        let nonlinear = DSP.nonlinear(linear, strength: nonlinearStrength)
        let envelope = (0..<count).map { 2 * abs(cos(.pi * difference * Double($0) / rate)) }
        return VStack(alignment: .leading, spacing: 20) {
            controls {
                slider("Tone separation Δf", value: $difference, range: 2...24, step: 1, unit: "Hz")
                slider("Nonlinearity α", value: $nonlinearStrength, range: 0...0.75, step: 0.05, unit: "relative")
            }
            metrics([("Tone 1", "128 Hz"), ("Tone 2", "\(Int(128 + difference)) Hz"), ("Envelope repeat rate", "\(Int(difference)) Hz")])
            HStack(alignment: .top, spacing: 16) {
                timePlot("Linear sum + envelope", traces: [timeTrace("x = tone 1 + tone 2", linear, rate: rate), timeTrace("± envelope", envelope, rate: rate, color: .orange, dashed: true), timeTrace("", envelope.map(-), rate: rate, color: .orange, dashed: true)], end: 500, amplitude: 2.2, summary: "Linear sum of 128 and \(Int(128 + difference)) hertz. Dashed envelope repeats \(Int(difference)) times per second; it is not included in the FFT.")
                frequencyPlot("Linear spectrum", traces: [spectrumTrace("x", linear, rate: rate)], end: 384, top: 1.1, summary: "Only two peaks at 128 and \(Int(128 + difference)) hertz. No peak at the difference frequency \(Int(difference)) hertz.")
            }
            explanation("THE IDENTITY", "cos(2πf₁t) + cos(2πf₂t) = 2 cos(π(f₂ − f₁)t) cos(π(f₁ + f₂)t). The magnitude envelope is 2|cos(πΔft)|. Its repetition rate is Δf, but the linear sum still contains only the original two spectral lines.")
            HStack(alignment: .top, spacing: 16) {
                timePlot("After a toy nonlinearity", traces: [timeTrace("y = x + αx²", nonlinear, rate: rate, color: .purple)], end: 500, amplitude: 5.2, summary: "The explicitly nonlinear output x plus alpha x squared, alpha \(nonlinearStrength).")
                frequencyPlot("Nonlinear spectrum", traces: [spectrumTrace("y", nonlinear, rate: rate, color: .purple)], end: 384, top: 1.1, summary: "Original tones plus DC, a difference component at \(Int(difference)) hertz, sum at \(Int(256 + difference)) hertz, and second harmonics. Added components vanish when alpha is zero.")
            }
            explanation("A NEW COMPONENT NEEDS A NEW OPERATION", "The square term introduces an actual Δf spectral line of amplitude α, plus DC (α), a sum-frequency line (α), and second harmonics (α/2 each). Set α to zero to remove them. This is a mathematical nonlinearity, not a prediction of speaker, air, or microphone performance.")
        }
    }

    private var recording: some View {
        let simulation = RecordingSimulation(cutoff: cutoff, sampleRate: sampleRate, count: max(fftCount, Int(sampleRate)))
        let original = Array(simulation.original.prefix(8192))
        let filtered = Array(simulation.filtered.prefix(8192))
        let short = Array(simulation.sampled.prefix(256))
        let selected = Array(simulation.sampled.prefix(fftCount))
        let alias = DSP.alias(900, sampleRate: sampleRate)
        return VStack(alignment: .leading, spacing: 20) {
            controls {
                slider("High-pass cutoff", value: $cutoff, range: 0...200, step: 5, unit: "Hz")
                VStack(alignment: .leading) {
                    Text("Sampling rate").font(.caption)
                    Picker("Sampling rate", selection: $sampleRate) {
                        ForEach([1024.0, 2048.0, 4096.0], id: \.self) { Text("\(Int($0)) Hz").tag($0) }
                    }.labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("FFT length / window").font(.caption)
                    Picker("FFT length", selection: $fftCount) { ForEach([256, 512, 1024, 2048], id: \.self) { Text("\($0) samples").tag($0) } }.labelsHidden()
                    Picker("Window function", selection: $window) { ForEach(FFTWindow.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
                }
            }
            explanation("SOURCE & ORDER", "Synthetic tones: 20 Hz (0.70), 180 Hz (0.35), and 900 Hz (0.25). First apply a modeled high-pass at an 8,192 Hz reference rate, then sample at the selected rate, then analyze a finite window. No microphone or codec is modeled.")
            HStack(alignment: .top, spacing: 16) {
                timePlot("1 · Before high-pass", traces: [timeTrace("Reference input", original, rate: 8192)], end: 150, amplitude: 1.4, summary: "Input tones 20, 180, 900 hertz. Time axis 0 to 150 milliseconds.")
                timePlot("After high-pass", traces: [timeTrace("Filtered reference", filtered, rate: 8192, color: .orange)], end: 150, amplitude: 1.4, summary: "Filtered signal, cutoff \(Int(cutoff)) hertz. The 20 hertz amplitude is \(String(format: "%.3f", 0.7 * DSP.highPassGain(frequency: 20, cutoff: cutoff, sampleRate: 8192))).")
            }
            explanation("FILTERING ATTENUATES", "This first-order high-pass rolls off gradually; it is not a brick wall. At its cutoff the steady-state amplitude is about 0.707 of input (−3 dB). Cutoff 0 bypasses it. A two-second warmup excludes the startup transient. Real hardware responses vary.")
            HStack(alignment: .top, spacing: 16) {
                frequencyPlot("2 · Before sampling", traces: [spectrumTrace("Filtered reference", filtered, rate: 8192, window: window, color: .orange)], end: 1200, top: 0.8, summary: "Filtered reference peaks at 20, 180, and 900 hertz, with 1 hertz bin spacing.")
                frequencyPlot("After sampling", traces: [spectrumTrace("Sampled signal", selected, rate: sampleRate, window: window, color: .purple)], end: 1200, top: 0.8, marker: sampleRate / 2, summary: "Nyquist frequency \(Int(sampleRate / 2)) hertz. The 900 hertz input appears at \(Int(alias)) hertz. Bins above Nyquist are not represented.")
            }
            explanation("SAMPLING CAN FOLD FREQUENCIES", "Nyquist = \(Int(sampleRate / 2)) Hz (dashed line when visible). The 900 Hz tone maps to \(Int(alias)) Hz. This sampler deliberately has no anti-alias low-pass, so above-Nyquist tones fold into lower bins. A high-pass does not prevent this. A practical sampling system can use an anti-alias filter before sampling; this simulation does not assert any universal device design.")
            HStack(alignment: .top, spacing: 16) {
                frequencyPlot("3 · Short observation: 256 samples", traces: [spectrumTrace("\(window.rawValue) window", short, rate: sampleRate, window: window)], end: 240, top: 0.8, summary: "Short FFT: bin spacing \(sampleRate / 256) hertz; duration \(256 / sampleRate) seconds.")
                frequencyPlot("Selected observation: \(fftCount) samples", traces: [spectrumTrace("\(window.rawValue) window", selected, rate: sampleRate, window: window, color: .purple)], end: 240, top: 0.8, summary: "Selected FFT: bin spacing \(sampleRate / Double(fftCount)) hertz; duration \(Double(fftCount) / sampleRate) seconds.")
            }
            metrics([("Bin spacing · fₛ/N", String(format: "%.2f Hz", sampleRate / Double(fftCount))), ("Observation · N/fₛ", String(format: "%.3f s", Double(fftCount) / sampleRate)), ("20 Hz filter gain", String(format: "%.3f ×", DSP.highPassGain(frequency: 20, cutoff: cutoff, sampleRate: 8192)))])
            explanation("WINDOW LENGTH IS NOT A FILTER", "Longer observations give closer frequency bins. The Hann window reduces sidelobes but widens each peak’s main lobe compared with a rectangular window. Bin spacing is not the same as the ability to resolve two tones. Coherent-gain correction preserves bin-centered tone amplitude; off-bin peaks can read lower. An FFT does not erase low frequencies or determine whether a signal can be recorded.")
        }
    }

    private func modulationRow(_ title: String, values: [Double], color: Color, top: Double, summary: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            timePlot(title, traces: [timeTrace("Time signal", values, rate: rate, color: color)], end: 40, amplitude: top, summary: summary)
            frequencyPlot("\(title) · spectrum", traces: [spectrumTrace("Spectrum", values, rate: rate, color: color)], end: 900, top: 1.1, summary: summary)
        }
    }
    private func timePlot(_ title: String, traces: [Trace], end: Double, amplitude: Double, summary: String) -> some View {
        Plot(title: title, traces: traces, xRange: 0...end, yRange: -amplitude...amplitude, xLabel: "Time (ms)", summary: summary, playing: playing, start: started, frozen: frozen)
            .frame(maxWidth: .infinity)
    }
    private func frequencyPlot(_ title: String, traces: [Trace], end: Double, top: Double, marker: Double? = nil, summary: String) -> some View {
        Plot(title: title, traces: traces, xRange: 0...end, yRange: 0...top, xLabel: "Frequency (Hz)", yLabel: "Peak amplitude (one-sided, relative)", summary: summary, isSpectrum: true, marker: marker)
            .frame(maxWidth: .infinity)
    }
    private func controls<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 24, content: content).padding(18)
            .background(.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2)))) \(unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step) { Text(title) }.labelsHidden().accessibilityValue("\(value.wrappedValue) \(unit)")
        }.frame(maxWidth: .infinity)
    }
    private func explanation(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).tracking(1).foregroundStyle(.blue)
            Text(body).font(.callout).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func metrics(_ items: [(String, String)]) -> some View {
        HStack(spacing: 24) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 5) {
                    Text(items[i].0).font(.caption).foregroundStyle(.secondary)
                    Text(items[i].1).font(.headline.monospacedDigit())
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(18).background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    private func togglePlayback() {
        if playing { frozen += Date().timeIntervalSince(started) } else { started = Date() }
        playing.toggle()
        audio.space.pauseThrow(!playing)
    }
    private func reset() {
        audio.stop()
        switch lesson {
        case .soundboard: resetToken = UUID(); audio.audibleEnabled = false; audio.volume = 0.15
        case .speech:
            audio.clearSpeech(); audio.clearWords = true; audio.wordDefinition = 0.5; audio.speechCarrierLevel = 0.06
            speechText = "Hello from Syndrome. Explore the signal, understand the sound."; resetToken = UUID()
        case .range: resetToken = UUID()
        case .bluetooth:
            UserDefaults.standard.removeObject(forKey: "preparedBluetoothDeviceLabel")
            UserDefaults.standard.removeObject(forKey: "preparedBluetoothProfile")
            UserDefaults.standard.removeObject(forKey: "bluetoothPlanSaved")
        case .waveforms: frequency = 64; amplitude = 0.8
        case .modulation: messageFrequency = 60; carrier = 400; depth = 0.8
        case .beats: difference = 8; nonlinearStrength = 0.5
        case .recording: cutoff = 60; sampleRate = 1024; fftCount = 1024; window = .hann
        }
        frozen = 0; started = Date()
    }
}
