# Syndrome™ DSP and spatial models

By: Premise LLC's Disinformation Labs™

See the [README](../README.md) for downloads, setup, and building.

## Features

- **Master frequency:** an always-visible 0.50–2,000 Hz control with a logarithmic slider, 0.01 Hz stepper, exact numeric entry, and presets below and above 19.75 Hz. It is remembered between launches and controls the Pure tone pad, SubVocal carrier simulation, and Range waveform. It does not repitch the ordinary speech voice or override the other pads/learning lessons. Changing frequency stops playback. Use the shared Audio toggle, level and two-second test-tone button for intentional output. Audibility depends on the listener, device and level; frequency is not a mute switch. The master reset returns to 19.75 Hz; section Reset leaves the master setting unchanged.
- **Sound Board:** four selectable synthetic pads: master-frequency sine, decaying 330/660/990 Hz chime, 220/224 Hz beats, and a 180–880 Hz chirp. Selection updates the waveform/spectrum without autoplay. Enable audible previews, then press Play for a two-second preview. Output starts at 15% app volume and has short fades. The Pure tone spectrum uses an eight-second observation to resolve low frequencies; playback is two seconds. Plot axes follow the selected frequency.
- **Text to SubVocal Speech:** Clear words + carrier now defaults to full speech with adjustable definition and a quiet carrier underlay; see the clearer-words section below. Select Carrier only for the original simulation. Type up to 300 characters and press **Generate preview**. An installed macOS voice renders ordinary speech into memory without playing it. The actual speech waveform appears beside an adjustable carrier illustration. Enable Audio and press **Play audible speech** for the ordinary voice, or **Play carrier simulation** for the modulated tone centred on the master frequency. Choose **Cadence only** or **Cadence + intonation** (default), then adjust Intonation strength and press Play to compare. The first keeps the carrier frequency fixed; the second follows estimated relative vocal pitch. Separate plots show estimated voice pitch and actual carrier-frequency motion. The carrier simulation sounds like a modulated tone and does not preserve intelligible words. Changed text requires regeneration before playback. Rendering is capped at 45 seconds of audio with a 25-second generation timeout.
- **Spatial sphere:** shared X/Y/Z controls in Sound Board and SubVocal, in metres. Three draggable plane views, exact coordinate entry, six axis throws, distance/direction metrics, an adjustable inner balance radius and live macOS headphone 3D previews. Position and throw settings carry between the two tabs.
- **Range:** adjustable distance from 1–100 m and assumed excess loss of 0–0.5 dB/m. Side-by-side reference/received signals, relative amplitude, delay and attenuation curve. This is a mathematical free-field model, not a calibrated prediction of audibility, speech intelligibility, speaker output or Bluetooth range.
- **Bluetooth Prep:** local device label and intended-use preferences. No Bluetooth framework, permission request, manager, scan, pairing, advertisement or connection code. The Scan, Pair and Connect controls are visibly disabled. Actual audio follows the output device already selected in macOS; Syndrome does not change routing or pair devices.
- **Learning views:** the original Waveforms, Modulation, Beats and Recording lessons remain available, with labeled axes, explicit assumptions and side-by-side plots.

Audio is disabled by default, starts only through an explicit Play action, and stops when disabled, when changing sections, or when the app becomes inactive. **Stop audio** controls audible playback separately from **Pause**, which controls the visual cursor and active sphere motion (⌘⇧P); audio keeps playing at the held position. No microphone capture, haptics, network calls, background monitoring, transmission or hidden-signal detection is implemented. No speech text or audio is stored on disk by the app. The master frequency and Bluetooth preparation fields are stored locally in app preferences.

## Clearer spoken words

**Clear words + carrier** is the default SubVocal output selection. Generate the text, enable Audio, and press **Play clear words** or **Play clear words in space**. This keeps the actual speech recording at its original sample rate and duration, with a quiet cadence/intonation carrier underneath. The master frequency sets the underlay, not the voice's pitch or speech bandwidth. **Carrier only** still provides the previous tone simulation, and **Play audible speech** is the unprocessed voice comparison. All three use the shared spatial sphere when 3D preview is on.

**Word definition** adds a gentle presence shelf: `voice + 0.6 × definition × highPass(voice, 1200 Hz)`, using the existing first-order bilinear high-pass. At maximum definition, the high-frequency shelf approaches about +4.1 dB before headroom adjustment; low-frequency vocal body remains. The cutoff is capped at 20% of the input sample rate. The processed voice is only attenuated when necessary to cap its peak at 0.85; quiet voices are not automatically amplified.

**Carrier underlay** ranges from 0–25%, initially 6%. The mix is `(1 − underlay) × processedVoice + underlay × carrier`, retaining peak headroom even when the two align. Definition defaults to 50%. Zero underlay removes the tone; both controls at zero retain the original voice except necessary peak headroom. Five-millisecond boundary fades are applied before playback. Spatial gain follows afterward, so moving farther away still reduces level. Before/after plots show the actual voice and mix before fades/spatial rendering; carrier-only plots are labeled separately.

Clear words uses ordinary audible speech bandwidth. It does not encode intelligible speech exclusively into an infrasonic band or recover words from the carrier. Reducing the underlay reduces competition with the voice; actual perceived clarity depends on the text, voice and playback setup. Use **Centre** to compare without distance attenuation. Output mode and clarity controls remain shared during tab navigation and reset with the SubVocal section's Reset button.

## What the carrier mode does

A pure tone, including the original 19.75 Hz preset, cannot reproduce intelligible words by itself. Ordinary speech playback and carrier playback are separate explicit actions.

Both modes use an approximately 30 ms short-time RMS envelope from actual synthesized speech, normalized to shape carrier amplitude at an 8,192 Hz simulation rate. **Cadence only** multiplies that envelope by `sin(2π × masterFrequency × t)`.

**Cadence + intonation** estimates vocal fundamental frequency from locally generated speech using normalized autocorrelation in 60 ms frames at 10 ms intervals, over 60–500 Hz. Two one-pole 800 Hz low-pass stages precede resampling to a 4,000 Hz analysis rate. Low-energy or low-periodicity frames are unvoiced. Interpolated autocorrelation peak heights reduce integer-lag octave errors, but this educational tracker is not error-free. The UI reports voiced-frame coverage; gaps in the source-pitch plot indicate unavailable estimates.

Pitch is mapped relative to the utterance’s median voiced frequency: `semitones = 12 log2(F0 / medianF0)`, limited to ±12 semitones and scaled by Intonation strength (0–100%). Interpolated offsets receive 25 ms smoothing. Carrier frequency is `masterFrequency × 2^(semitones/12)`, bounded between 0.25 Hz and 45% of the simulation sample rate. Phase is obtained by integrating frequency, so pitch changes do not reset the oscillator. Unvoiced frames return toward the centre frequency while the amplitude envelope still follows cadence; silence remains silent. A track with no reliable pitch falls back to cadence-only synthesis. The master is a centre setting, not a bound on the full frequency excursion.

This preserves rhythm and an estimated intonation pattern, not consonant/vowel detail or intelligible words. The distinction between temporal envelopes and pitch-bearing detail is supported by [Smith, Delgutte & Oxenham’s auditory-chimaera research](https://www.ee.columbia.edu/~dpwe/e6820/papers/SmithDO02-chimaeric.pdf); that study used audible frequency bands and does not demonstrate intelligible infrasonic speech. Familiarity with the phrase is not a test of how much an unfamiliar listener can recover.

Amplitude and frequency modulation both introduce sidebands; the result is not confined to one frequency or an arbitrarily narrow band. The carrier buffer is sent to the audio player only by **Play carrier simulation**, with 20 ms edge fades. Preparing the simulation does not start audio.

Its spectrum shows the first eight seconds, zero-padded when shorter, with 0.125 Hz bin spacing and magnitude normalized to its largest bin. Padding does not improve actual frequency resolution. Time overviews preserve the minimum and maximum in each display block. Speech rendering needs an installed macOS voice; the app does not download voices.

## Virtual room and apparition

The shared Spatial sphere panel now opens in **Room + apparition** view. **XYZ planes** switches back to the three coordinate maps. Select **Place in room** to put the voice origin two metres in front of the listener (or nearer in a small room) and face it toward the listener. In **Place apparition** interaction mode, click or drag the scene to place X/Z at the current Y. The **Voice height above floor** field changes Y. The original X/Y/Z fields, sliders, throws and balance sphere all address the same source, so pad, clear-words, ordinary-speech and carrier previews follow it. A nearby Play button lets you start audio before moving the apparition.

The point cloud is generated from an editable rectangular room: initially 8 m wide, 10 m deep and 3 m high. It is a lidar-style visualization, not an imported or live lidar scan. The origin is the speaker/listener reference at 1.6 m above the floor (floor Y = −1.6 m); the listener faces −Z. The apparition's head marker is the mono audio source. Its translucent procedural body and point rings rotate with it. Room walls remain visual guides: no reflection, occlusion, collision or acoustic calibration is inferred. A source outside the room is labeled; Place in room returns it to the visible room. Existing throws still use the ±50 m global bounds.

**Yaw** turns around Y, **pitch** tilts around X and **roll** leans around Z. These are right-handed Euler rotations, applied local roll first, then pitch, then yaw. The body faces local −Z. **Face listener** computes yaw/pitch toward the origin and clears roll. Rotation alone does not change the sound of the default omnidirectional point source.

Enable **Directional voice** for an optional broad facing pattern: `gain = 0.625 + 0.375 × cos(theta)`, where theta is the angle between the apparition's forward direction and the direction toward the listener. This gives 1× forward, 0.625× sideways and 0.25× rearward, multiplying the existing distance gain. Roll does not change this axially symmetric pattern. Coincident source/listener positions use unity facing gain. The displayed facing gain is this factor, not a calibrated physical radiation pattern. Rotation and directionality update playing audio live, while room dimension and camera changes do not affect audio.

**Orbit view** uses dragging to move only the viewing camera. Front, Top and Reset view provide keyboard-accessible presets. The camera never rotates the virtual listener. Placement uses the inverse orthographic projection at the source's current height; it does not infer depth from a flat click or measure a room. All dimensions, positions and rotations have labeled controls or equivalent XYZ fields.

For spatial cues, enable 3D preview and play a sound, then move the apparition. Headphone HRTF rendering simulates sound arriving from its position. Ordinary speakers cannot be assumed to put audio at that physical location. No lidar, camera, microphone, head tracking, Bluetooth scan/pairing or sensor capture is added.

## Spatial sphere

On **Sound Board**, select a pad; on **SubVocal Speech**, generate a phrase and choose cadence/intonation. Both tabs show the same **Spatial sphere** controls. Enable Audio and use a Play button, then drag a map or press a **THROW** direction. The panel includes a nearby replay button. Sphere movement also works silently when Audio is off. **3D preview** is enabled initially but never starts audio by itself; turning it off bypasses spatial processing on the next Play.

- **Axes:** X increases to the right, Y upward, Z rearward. The fixed virtual listener faces −Z. X/Y, X/Z and Z/Y projections each have four quadrants; adding the third sign produces eight octants. Zero coordinates are labeled explicitly as axis planes. Six throw buttons represent ±X, ±Y and ±Z, not six quadrants.
- **Origin:** the central speaker icon marks the shared speaker/listener reference, not a measured physical speaker layout. The moving ball is a virtual sound source. All maps show the same point; dragging changes only the two displayed coordinates. Labeled numeric fields and keyboard-adjustable sliders provide alternatives to dragging. The map automatically expands in 10 m steps; each coordinate is bounded to ±50 m. A drag keeps its initial scale until release.
- **Inner balance sphere:** the dashed disk in each projection shows radius R (0.25–10 m). Distance gain is 1 inside R and R/r outside, where r = √(x²+y²+z²). It never boosts nearby audio. The centre is channel-balanced; away from centre, directional rendering still applies inside the radius. The displayed gain is the distance factor before HRTF filtering and master volume, not an SPL measurement or exact per-channel level.
- **Throws:** travel (0.5–50 m) is measured from the current position along the chosen signed axis, at a constant speed (0.5–25 m/s). A throw clips at the coordinate boundary and stops exactly there. A throw toward the opposite side can pass through the origin. Motion pauses/resumes, and Centre or direct coordinate edits cancel the trajectory. Throws never autoplay or loop audio. A finite clip can end before its throw; replay continues at the current position. Stop audio, Audio off, switching sections, and app inactivity stop motion. The position remains when switching sections; **Reset space** restores only the spatial settings. Nothing is measured from devices.
- **Audio:** mono pad, ordinary speech, carrier and master-test previews feed `AVAudioPlayerNode → AVAudioEnvironmentNode → stereo mixer`. HRTF HQ, then HRTF, is selected when supported; otherwise the UI labels equal-power stereo pan. Live coordinate/radius changes update the native environment without regenerating the speech/carrier. The native inverse-distance model uses referenceDistance=R and rolloffFactor=1. No reverberation is added. A separate observable controller keeps animation from recalculating the speech FFT every frame.

The direction model follows [Apple’s 3D audio coordinate system](https://developer.apple.com/documentation/avfaudio/avaudio3dpoint); HRTF is a headphone cue simulation. Ordinary speakers are not a calibrated array, and these controls do not steer a beam or place audio at a remote physical point. Direction and depth may be weak or ambiguous, especially for narrow low-frequency tones. A plotted travel-time estimate r/343 is informational; this preview does not apply propagation delay or Doppler shift. Walls, obstacles, room reflections and measured transducer responses are excluded. Before-spatial source waveform plots remain unchanged. The separate **Range** lesson bypasses this sphere so attenuation is not counted twice. Bluetooth remains disconnected by the app.

## Range assumptions

For distance `r ≥ 1 m` and assumed excess loss `a` in dB/m:

- Pressure ratio: `(1/r) × 10^(−a(r−1)/20)` relative to an assumed amplitude of one at one metre.
- Level change: `−20 log10(r) − a(r−1)` dB.
- Delay from source emission: `r / 343` seconds, using an assumed sound speed of 343 m/s.

With no excess loss, pressure follows `1/r` and intensity follows `1/r²`. The reference waveform uses emission time; the receiver uses arrival time. Reflections, obstacles, background noise, directivity, transducer response and near-field effects are excluded. No maximum intelligible range is computed. **Play reference** and **Play at distance** provide two-second tone comparisons using the master frequency and audio level; the latter retains the modeled attenuation without automatic normalization.

## DSP learning conventions

Signals use dimensionless amplitude, not dB SPL. Time is `sampleIndex / sampleRate`, converted to milliseconds where labeled. One-sided frequency axes use `k × sampleRate / N` through Nyquist.

The complex vDSP forward FFT is unnormalized. Peak amplitude is `2 × abs(X[k]) / sum(window)`, with a factor of one for DC and Nyquist. The periodic Hann window is `0.5 − 0.5 cos(2πn/N)`. Coherent-gain correction preserves isolated bin-centered tones away from endpoints; off-bin peaks can read lower. See [Apple’s Fourier transform conventions](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html).

The Recording lesson uses an 8,192 Hz numerical reference, first-order prewarped bilinear high-pass, two-second warmup, and integer decimation deliberately lacking an anti-alias low-pass. Its synthetic tones are 20, 180 and 900 Hz. FFT observation length and window type are independently adjustable. It models no codec and asserts no universal microphone response.

Modulation contrasts full-carrier AM with analytically synthesized upper SSB. Translation preserves tone spacing. Beats contrasts the exact linear cosine sum with `y = x + αx²`; only the nonlinear model adds an actual difference-frequency line.

## Build in Xcode

Open `Syndrome.xcodeproj`, choose the **Syndrome** scheme and **My Mac**, then Run (⌘R). Local ad-hoc signing requires no developer account. The native project uses the same sources as the command-line build.

Tests are a standalone executable, `SyndromeChecks`, so they run even on Command Line Tools installations without XCTest. Use `./scripts/test.sh`; the Xcode scheme does not contain XCTest tests.

## Logo

`Sources/Syndrome/Brand.swift` defines the original alien-head shape and app icon. Artwork is defined in SwiftUI and rendered locally. `output.png` is the 1024 px rendered icon and `Resources/Syndrome.icns` is the packaged macOS icon. To regenerate after editing the shapes:

```sh
./scripts/build-icon.sh
./scripts/build-app.sh
```

## Verification

All 711 deterministic checks pass: FFT scaling and peaks, AM/SSB, beats and nonlinear components, high-pass response, aliasing, windows, bounded/faded sound pads, master-frequency bounds/logarithmic control, carrier and pad spectral peaks at all presets from 0.5 to 2,000 Hz, fractional-frequency synthesis, RMS-envelope edge cases, range equations, PCM WAV encoding, simulation edge fades that preserve attenuation, known-pitch and harmonic fixtures, rising pitch contours, silence/noise rejection, zero-strength equivalence, cadence gaps, frequency bounds, and continuous-phase frequency modulation. The suite never plays audio or connects devices. The Xcode project plist is validated; an actual Xcode build has not been run.

Local speech integration also passed `./scripts/test-speech.sh`: 50,239 generated samples at 22,050 Hz, repeated-completion handling, pitch extraction from generated speech and zero-volume speech, prosody-carrier, and range playback through the system output, audio-toggle gating/status, and render cancellation. This optional integration check requires an installed voice and working audio output. Its audio level is zero throughout.

Spatial verification: `./scripts/test-spatial.sh` renders the native audio graph offline, without speaker output, checking centre channel balance, distance doubling, the inner radius, left/right panning, HRTF front/rear and height response, and all studio sample rates. It also verifies silent throws, pause/resume, exact completion, cancellation and reset. The deterministic suite covers octants, projection round trips, held coordinates, gain boundaries and all six bounded throws. `./scripts/test-speech.sh` additionally checks zero-volume live carrier movement, replacing playing buffers without stale completion callbacks, and stopping motion/audio together.

Clear-word checks cover exact bypass, preservation of a 6 kHz speech-band fixture, relative presence gain, native sample rate and duration, silence, peak headroom, no quiet-voice normalization and separate carrier mixing. The muted speech integration also exercises clear-word playback, spatial movement, output selection and stopping stale previews after definition changes. These verify signal behavior, not human intelligibility.

Room/orientation verification covers deterministic surface points, room limits, orthographic projection inversion, preserved height, unit rotation vectors, Euler axis signs, face-listener alignment and rotationally symmetric directionality. Offline native rendering confirms the 0.25 rear/forward amplitude ratio. Controller checks confirm that camera and room edits do not change audio, while source orientation and directionality are connected.
