// Copyright 2026 Premise LLC
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import Combine
import Foundation
#if SWIFT_PACKAGE
import SyndromeDSP
#endif

@MainActor
final class StudioAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var audibleEnabled = false {
        didSet {
            if !audibleEnabled { stop() }
            else if !isPlaying && !rendering { status = "Audio ready. Choose a Play button to hear a preview." }
        }
    }
    @Published var volume = 0.15 { didSet { player?.volume = Float(volume); spatialGraph?.engine.mainMixerNode.outputVolume = Float(volume) } }
    @Published var spatialEnabled = true { didSet { if oldValue != spatialEnabled { stop() } } }
    let space = SpatialController()
    @Published var clearWords = true { didSet { if oldValue != clearWords { stop() } } }
    @Published var wordDefinition = 0.5 { didSet { if oldValue != wordDefinition { stop() } } }
    @Published var speechCarrierLevel = 0.06 { didSet { if oldValue != speechCarrierLevel { stop() } } }
    @Published private(set) var spatialRenderer = "Headphone 3D · selected on Play"
    @Published private(set) var isPlaying = false
    @Published private(set) var rendering = false
    @Published private(set) var status = "Audio off. Enable Audio, then choose a Play button."
    @Published private(set) var speechSamples: [Double] = []
    @Published private(set) var pitchTrack: SpeechPitchTrack?
    @Published private(set) var speechRate = 22050.0
    @Published private(set) var renderedText = ""
    private var player: AVAudioPlayer?
    private var spatialGraph: SpatialAudioGraph?
    private var playbackID = UUID()
    private let synthesizer = AVSpeechSynthesizer()
    private var renderID = UUID()
    private var scratch: [Double] = []
    private var watchdog: Task<Void, Never>?

    override init() {
        super.init()
        space.onChange = { [weak self] in
            guard let self else { return }
            self.spatialGraph?.update(position: self.space.spatialPosition, radius: self.space.balanceRadius, orientation: self.space.orientation, directional: self.space.directionalVoice)
        }
    }

    func play(_ samples: [Double], sampleRate: Double, label: String, spatial: Bool = true) {
        guard audibleEnabled else { status = "Enable audible previews to hear \(label)."; return }
        guard !samples.isEmpty else { status = "Generate a preview first."; return }
        stop(freezeMotion: false)
        do {
            if spatial && spatialEnabled {
                let graph = SpatialAudioGraph(sampleRate: sampleRate)
                guard let buffer = graph.buffer(samples) else { status = "Could not prepare spatial audio."; return }
                graph.update(position: space.spatialPosition, radius: space.balanceRadius, orientation: space.orientation, directional: space.directionalVoice)
                graph.engine.mainMixerNode.outputVolume = Float(volume)
                let id = UUID(); playbackID = id
                spatialGraph = graph
                spatialRenderer = graph.rendererName
                graph.source.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.playbackID == id else { return }
                        self.stop(freezeMotion: false)
                        self.status = "Preview finished."
                    }
                }
                try graph.engine.start()
                graph.source.play()
                isPlaying = true
                status = "Playing \(label) · \(graph.rendererName). Move or throw the sphere live."
                return
            }
            let audio = try AVAudioPlayer(data: PCMEncoding.wav(samples: samples, sampleRate: Int(sampleRate)))
            audio.delegate = self
            audio.volume = Float(volume)
            guard audio.prepareToPlay(), audio.play() else { status = "Audio output could not start. Check the current macOS output device."; return }
            player = audio
            isPlaying = true
            status = "Playing \(label) through the current macOS output."
        } catch { stop(); status = "Audio preview unavailable: \(error.localizedDescription)" }
    }

    func playCarrier(frequency: Double, intonationDepth: Double = 0) {
        guard !speechSamples.isEmpty else { status = "Generate a speech preview first."; return }
        let simulation = SubVocalSimulation(speech: speechSamples, speechRate: speechRate, carrier: MasterFrequency.normalized(frequency), pitchTrack: pitchTrack, intonationDepth: intonationDepth)
        play(DSP.faded(simulation.modulated, sampleRate: simulation.sampleRate), sampleRate: simulation.sampleRate,
             label: "\(String(format: "%.2f", frequency)) Hz carrier · \(intonationDepth > 0 ? "cadence + intonation" : "cadence only")")
    }

    func playSpeechPreview(frequency: Double, intonationDepth: Double) {
        guard clearWords else { playCarrier(frequency: frequency, intonationDepth: intonationDepth); return }
        guard !speechSamples.isEmpty else { status = "Generate a speech preview first."; return }
        let mix = ClearSpeechMix(speech: speechSamples, speechRate: speechRate,
                                 carrier: MasterFrequency.normalized(frequency), pitchTrack: pitchTrack,
                                 intonationDepth: intonationDepth, definition: wordDefinition, carrierLevel: speechCarrierLevel)
        play(DSP.faded(mix.samples, sampleRate: mix.sampleRate, seconds: 0.005), sampleRate: mix.sampleRate,
             label: "clear words + \(String(format: "%.2f", frequency)) Hz carrier underlay · audible speech bandwidth")
    }

    func playRange(frequency: Double, distance: Double?, excessLoss: Double) {
        let rate = 8192.0
        let gain = distance.map { RangeModel.gain(distance: $0, excessLossDBPerMetre: excessLoss) } ?? 1
        let delay = distance.map { RangeModel.delay(distance: $0) } ?? 0
        let samples = DSP.tone(MasterFrequency.normalized(frequency), amplitude: gain, sampleRate: rate, count: 16384, phase: -2 * .pi * frequency * delay)
        play(DSP.faded(samples, sampleRate: rate), sampleRate: rate,
             label: distance.map { "range simulation at \($0.formatted()) metres" } ?? "range reference", spatial: false)
    }

    func stop(freezeMotion: Bool = true) {
        playbackID = UUID()
        if freezeMotion { space.stopThrow() }
        spatialGraph?.source.stop()
        spatialGraph?.engine.stop()
        spatialGraph = nil
        player?.stop()
        player = nil
        isPlaying = false
        if !rendering { status = audibleEnabled ? "Audio ready. Nothing playing." : "Audio off. Enable Audio, then choose a Play button." }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop(freezeMotion: false)
            self.status = flag ? "Preview finished." : "Audio preview interrupted."
        }
    }

    func cancelRender() {
        let wasRendering = rendering
        renderID = UUID()
        watchdog?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        scratch = []
        rendering = false
        if wasRendering { status = "Speech generation cancelled." }
    }

    func clearSpeech() {
        cancelRender(); stop()
        speechSamples = []; pitchTrack = nil; renderedText = ""
    }

    func renderSpeech(_ text: String) {
        cancelRender(); stop()
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !trimmed.isEmpty else { status = "Type a message first."; return }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        guard let voice = voices.first(where: { $0.language == "en-US" && $0.quality == .default }) ?? voices.first(where: { $0.language.hasPrefix("en") }) ?? voices.first else {
            status = "No installed speech voice is available. Install a macOS voice to enable local text-to-speech."
            return
        }
        let id = UUID(); renderID = id
        rendering = true; speechSamples = []; pitchTrack = nil; renderedText = ""
        status = "Generating speech locally into memory. No sound is playing."
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            let rate = pcm.format.sampleRate
            let final = pcm.frameLength == 0
            let samples = Self.extract(pcm)
            DispatchQueue.main.async {
                guard let self, self.renderID == id, self.rendering else { return }
                if !samples.isEmpty {
                    if !self.scratch.isEmpty && self.speechRate != rate {
                        self.cancelRender(); self.status = "Voice changed sample rate during rendering. Try a shorter message."; return
                    }
                    self.speechRate = rate
                    self.scratch.append(contentsOf: samples)
                    if self.scratch.count > Int(rate * 45) {
                        self.cancelRender(); self.status = "Preview exceeded 45 seconds. Please shorten the message."; return
                    }
                }
                if final {
                    self.watchdog?.cancel()
                    self.speechSamples = self.scratch
                    self.scratch = []
                    self.rendering = false
                    self.pitchTrack = SpeechPitchTrack(speech: self.speechSamples, sampleRate: self.speechRate)
                    self.renderedText = self.speechSamples.isEmpty ? "" : trimmed
                    self.status = self.speechSamples.isEmpty ? "This voice returned no audio. Check installed macOS voices." : "Speech rendered locally · \(String(format: "%.1f", Double(self.speechSamples.count) / self.speechRate)) seconds. Choose Play speech or Play carrier simulation to hear a preview."
                }
            }
        }
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, let self, self.renderID == id, self.rendering else { return }
            self.cancelRender()
            self.status = "The installed voice did not finish. Try a shorter message or check macOS voice availability."
        }
    }

    nonisolated private static func extract(_ buffer: AVAudioPCMBuffer) -> [Double] {
        let count = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        guard count > 0 && channels > 0 else { return [] }
        let stride = buffer.stride
        if let floats = buffer.floatChannelData {
            return (0..<count).map { i in (0..<channels).reduce(0.0) { $0 + Double(floats[$1][i * stride]) } / Double(channels) }
        }
        if let integers = buffer.int16ChannelData {
            return (0..<count).map { i in (0..<channels).reduce(0.0) { $0 + Double(integers[$1][i * stride]) / 32768 } / Double(channels) }
        }
        if let integers = buffer.int32ChannelData {
            return (0..<count).map { i in (0..<channels).reduce(0.0) { $0 + Double(integers[$1][i * stride]) / 2147483648 } / Double(channels) }
        }
        return []
    }
}

/// Mono source -> fixed-listener virtual environment -> stereo output.
/// This graph can also render offline in integration checks without opening an output device.
@MainActor
final class SpatialAudioGraph {
    let engine = AVAudioEngine()
    let source = AVAudioPlayerNode()
    let environment = AVAudioEnvironmentNode()
    let format: AVAudioFormat
    let rendererName: String

    init(sampleRate: Double, headphones: Bool = true) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(source); engine.attach(environment)
        engine.connect(source, to: environment, format: format)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.connect(environment, to: engine.mainMixerNode, format: stereo)
        let available = environment.applicableRenderingAlgorithms.map(\.intValue)
        if headphones && available.contains(AVAudio3DMixingRenderingAlgorithm.HRTFHQ.rawValue) {
            source.renderingAlgorithm = .HRTFHQ
            rendererName = "Headphone 3D (HRTF HQ)"
        } else if headphones && available.contains(AVAudio3DMixingRenderingAlgorithm.HRTF.rawValue) {
            source.renderingAlgorithm = .HRTF
            rendererName = "Headphone 3D (HRTF)"
        } else {
            source.renderingAlgorithm = .equalPowerPanning
            rendererName = "Stereo pan fallback · elevation cues unavailable"
        }
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
        environment.reverbParameters.enable = false
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.rolloffFactor = 1
        source.reverbBlend = 0
    }

    func update(position: SpatialPoint, radius: Double, orientation: SourceOrientation = SourceOrientation(), directional: Bool = false) {
        let p = position.bounded
        environment.distanceAttenuationParameters.referenceDistance = Float(SpatialModel.radius(radius))
        source.position = AVAudio3DPoint(x: Float(p.x), y: Float(p.y), z: Float(p.z))
        source.volume = Float(orientation.gainTowardOrigin(from: p, directional: directional))
    }

    func buffer(_ samples: [Double]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        for (i, value) in samples.enumerated() { channel[i] = Float(value.isFinite ? min(1, max(-1, value)) : 0) }
        return buffer
    }
}

@MainActor
final class SpatialController: ObservableObject {
    @Published var orientation = SourceOrientation() { didSet { onChange?() } }
    @Published var directionalVoice = false { didSet { onChange?() } }
    @Published var roomWidth = 8.0
    @Published var roomDepth = 10.0
    @Published var roomHeight = 3.0
    @Published var roomCameraYaw = 35.0
    @Published var roomCameraElevation = 30.0
    var room: VirtualRoom { VirtualRoom(width: roomWidth, depth: roomDepth, height: roomHeight) }
    func placeInRoom() {
        moveSphere(to: SpatialPoint(z: -min(2, room.depth / 2 - 0.5)))
        orientation = .facingOrigin(from: spatialPosition)
    }
    func resetRoom() {
        roomWidth = 8; roomDepth = 10; roomHeight = 3
        roomCameraYaw = 35; roomCameraElevation = 30
        orientation = SourceOrientation(); directionalVoice = false
    }
    @Published var spatialPosition = SpatialPoint.zero {
        didSet {
            if spatialPosition != spatialPosition.bounded { spatialPosition = spatialPosition.bounded }
            onChange?()
        }
    }
    @Published var balanceRadius = 1.0 {
        didSet {
            let checked = SpatialModel.radius(balanceRadius)
            if balanceRadius != checked { balanceRadius = checked }
            onChange?()
        }
    }
    @Published var throwDistance = 10.0
    @Published var throwSpeed = 5.0
    @Published private(set) var isThrowing = false
    @Published private(set) var throwPaused = false
    @Published private(set) var throwDestination: SpatialPoint?
    var onChange: (() -> Void)?
    private var motionTask: Task<Void, Never>?
    func moveSphere(to position: SpatialPoint) { stopThrow(); spatialPosition = position.bounded }

    func stopThrow() {
        motionTask?.cancel(); motionTask = nil
        isThrowing = false; throwPaused = false; throwDestination = nil
    }

    func pauseThrow(_ paused: Bool) { if isThrowing { throwPaused = paused } }

    func launchSphere(axis: SpatialAxis, sign: Double) {
        stopThrow()
        let trajectory = SpatialThrow(start: spatialPosition, axis: axis, sign: sign, distance: throwDistance, speed: throwSpeed)
        guard trajectory.duration > 0 else { return }
        isThrowing = true; throwDestination = trajectory.end
        motionTask = Task { [weak self] in
            var elapsed = 0.0
            var previous = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_333_333)
                guard !Task.isCancelled, let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if !self.throwPaused {
                    elapsed += now - previous
                    self.spatialPosition = trajectory.position(at: elapsed)
                }
                previous = now
                if elapsed >= trajectory.duration { self.stopThrow(); return }
            }
        }
    }

    func resetSpatial() {
        stopThrow(); spatialPosition = .zero; balanceRadius = 1; throwDistance = 10; throwSpeed = 5; resetRoom()
    }

}
