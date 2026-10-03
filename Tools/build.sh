#!/bin/bash
# Builds (default) or tests the ProMe app from the command line.
# Usage:
#   Tools/build.sh                                   → build (macOS)
#   Tools/build.sh test                              → test (macOS)
#   Tools/build.sh build ios                         → build (iOS Simulator)
#   Tools/build.sh test ios                          → test (iOS Simulator, needs a booted device)
#   Tools/build.sh test ipados                       → test (iPad Simulator)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(xcode-select -p)" != *Xcode.app* && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ACTION="build"
PLATFORM="macos"
for arg in "$@"; do
    case "$arg" in
        build|test) ACTION="$arg" ;;
        macos) PLATFORM="macos" ;;
        ios) PLATFORM="ios" ;;
        ipados) PLATFORM="ipados" ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

case "$PLATFORM" in
    macos)
        DESTINATION='platform=macOS'
        ;;
    ios)
        # Use the first available iPhone simulator.
        DESTINATION=$(xcrun simctl list devices available | grep -m1 "iPhone" | sed -E 's/.*\(([0-9A-F-]{36})\).*/id=\1/' | sed 's/^/platform=iOS Simulator,/')
        ;;
    ipados)
        DESTINATION=$(xcrun simctl list devices available | grep -m1 "iPad" | sed -E 's/.*\(([0-9A-F-]{36})\).*/id=\1/' | sed 's/^/platform=iOS Simulator,/')
        ;;
esac

xcodebuild -project ProMe.xcodeproj -scheme ProMe -destination "$DESTINATION" "$ACTION"
