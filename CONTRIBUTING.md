# Contributing to Syndrome™

By: Premise LLC's Disinformation Labs™

Contributions are welcome through issues and pull requests. The project is licensed under Apache 2.0; contributions submitted for inclusion are handled under that license's contribution terms.

## Development

1. Fork and clone the repository.
2. Build with `swift build` or open `Syndrome.xcodeproj`.
3. Keep related changes focused and document any altered DSP assumptions.
4. Run `./scripts/test.sh`. Run the spatial and speech integration checks when changing their respective code paths.
5. Explain the behavior change and relevant validation in your pull request.

New app source files must be included in the Xcode project as well as discovered by SwiftPM. Keep LICENSE and NOTICE bundled by both build paths. Use Apache-2.0 SPDX identifiers for new project source files.

## Project conventions

- Label simulations, units and assumptions. Distinguish physical measurements from virtual models.
- Preserve explicit Play actions, Audio off on launch, and stop-on-inactivity behavior.
- Do not add network access, recording, sensors or device connections as incidental implementation details. Such changes require a separately scoped product discussion.
- Keep interactive controls keyboard-accessible and provide meaningful plot descriptions.
- Add deterministic checks for numerical changes. Avoid tests that merely duplicate an implementation.
- Do not commit build outputs, signing keys, credentials or private speech content.

For release procedures, see the README and `scripts/package-release.sh`.
