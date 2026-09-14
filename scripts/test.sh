#!/bin/zsh
# Copyright 2026 Premise LLC
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
cd "${0:A:h:h}"
swift run SyndromeChecks
