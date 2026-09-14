#!/bin/zsh
# Copyright 2026 Premise LLC
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
xcrun swiftc -parse-as-library Sources/SyndromeDSP/*.swift Sources/Syndrome/StudioAudio.swift scripts/VerifySpeech.swift -o .build/verify-speech
.build/verify-speech
