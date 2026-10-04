#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Reader/ReadingPanel.swift Sources/Reader/WindowVisibility.swift Tests/ReaderTests/WindowSmokeTests.swift -o .build/reader-window-tests
.build/reader-window-tests
