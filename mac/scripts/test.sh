#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/Reader/Preferences.swift Tests/ReaderTests/ReaderPolicyTests.swift -o .build/reader-policy-tests
.build/reader-policy-tests
swiftc Sources/Reader/Preferences.swift Sources/Reader/GlobalHotKey.swift Tests/ReaderTests/HotKeyTests.swift -o .build/reader-hotkey-tests
.build/reader-hotkey-tests
swiftc Sources/Reader/ReadingPanel.swift Tests/ReaderTests/ReadingKeyTests.swift -o .build/reader-reading-key-tests
.build/reader-reading-key-tests
