#!/bin/sh
# Rebuilds tests/fixtures from the real Swift formatters (see main.swift). Needs Xcode's swiftc.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT

swiftc -o "$build/swift_fixtures" \
    "$root"/xcode/Shared/Motion/*.swift \
    "$root"/xcode/Shared/WatchConnectivity/*.swift \
    "$root/xcode/Wristscope/Streaming/ComputerFormatter.swift" \
    "$root/tools/swift_fixtures/main.swift"
"$build/swift_fixtures" "$root/tests/fixtures"
echo "Wrote $root/tests/fixtures"
