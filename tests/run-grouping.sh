#!/bin/sh
# Grouping rules test: builds every source but the app entry point with the test as main.
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
cp tests/grouping.swift "$T/main.swift"
swiftc -swift-version 5 -target arm64-apple-macos14.0 "$T/main.swift" $(ls Sources/*.swift | grep -v main.swift) -o "$T/grouping"
"$T/grouping"
