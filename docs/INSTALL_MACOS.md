# Install Syndrome™ on macOS

By: Premise LLC's Disinformation Labs™

## Requirements

- macOS 14 Sonoma or later.
- Apple silicon or Intel Mac. The download contains both architectures.
- An installed macOS speech voice for text-to-speech. No Xcode or developer tools are required to run the download.

## Download and install

Download a DMG or ZIP from [GitHub Releases](https://github.com/Rali0s/Syndrome-TM/releases/latest).

1. Quit an older running copy of Syndrome before replacing it.
2. Open the DMG, or extract the ZIP.
3. Drag **Syndrome.app** to **Applications**, then launch it.
4. Audio starts disabled. Enable **Audio**, select a pad or generate a phrase, and press **Play**.

For a spatial preview, choose **Room + apparition**, then **Place in room**. Move the figure while audio plays. The room is a synthetic model; headphone rendering simulates source direction.

## Signing and first launch

This community release is **ad-hoc signed and not notarized by Apple**. Its signature checks bundle integrity; it does not identify Premise LLC through an Apple Developer ID certificate. A downloaded copy may be blocked by Gatekeeper.

If you trust this release and macOS blocks it, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). After attempting to launch it, macOS may offer **Open Anyway** in **System Settings → Privacy & Security**. Availability can depend on your Mac's management policy. Do not disable Gatekeeper globally. Building from the published source is another option.

## Verify the download

Download `SHA256SUMS.txt` alongside the matching ZIP or DMG. From that directory, run:

```sh
shasum -a 256 Syndrome-1.7.1-macOS-universal.zip
```

Compare the printed hash with the corresponding line in `SHA256SUMS.txt`. The hash detects a changed download; obtain the checksum from the same trusted release source.

The application itself can be checked with:

```sh
codesign --verify --deep --strict /Applications/Syndrome.app
```

## Troubleshooting

- **No audio:** enable Audio and press Play. Check the macOS output device, app level, spatial distance and facing gain. Use Centre for unity distance gain. Frequencies below your output's useful range may not be audible.
- **Words are unclear:** choose Clear words + carrier, keep Carrier underlay low, and compare with Play audible speech. Carrier only does not preserve intelligible words.
- **No speech voice:** install a voice through macOS settings. Syndrome does not download one.
- **Old interface:** quit all running copies and reopen the newly installed app.
- **Directional cues are weak:** compare on headphones. The virtual room does not physically steer speaker output or account for your room acoustics.

To uninstall, quit the app and remove Syndrome.app from Applications. Optional local preferences use the bundle identifier `edu.local.Syndrome`; the app does not save generated speech or typed phrases.
