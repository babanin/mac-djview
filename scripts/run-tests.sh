#!/bin/bash
# Run MacDjView unit tests.
# Requires: Xcode Command Line Tools (xcode-select --install)
#
# The Testing framework and its cross-import overlay live under the CLT
# Developer/Frameworks directory, so we pass -F (framework search) and -rpath
# flags explicitly. We also disable cross-import overlays to work around a
# CLT-only issue where _Testing_Foundation.swiftmodule is missing.

set -euo pipefail

FRAMEWORKS_DIR="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS_DIR" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS_DIR" \
    "$@"
