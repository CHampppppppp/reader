#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Reader/Preferences.swift Sources/Reader/ReadingPanel.swift Tests/ReaderTests/AppearanceTests.swift -parse-as-library -o .build/reader-appearance-tests
.build/reader-appearance-tests
