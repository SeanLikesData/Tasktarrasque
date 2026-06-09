#!/bin/bash
# Compile and run the Tasktarrasque model test suite.
#
# Like build.sh, this compiles directly with swiftc because SwiftPM does not
# link on a Command-Line-Tools-only machine. It builds a small command-line
# executable from the model sources plus Tests/main.swift and runs it. The
# executable exits non-zero if any assertion fails, so this script's exit code
# reflects the test result.
set -euo pipefail

cd "$(dirname "$0")"

SDK_PATH="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx14.0"

OUT_DIR=".build/tests"
mkdir -p "$OUT_DIR"
BIN="$OUT_DIR/TasktarrasqueTests"

# Only the model layer is under test. The view and app-entry sources are
# excluded so there is no second @main and no UI dependency.
SOURCES=(
    Sources/Tasktarrasque/Models/TaskModels.swift
    Sources/Tasktarrasque/Models/TaskInteractionModel.swift
    Sources/Tasktarrasque/Models/NoteStore.swift
    Sources/Tasktarrasque/Models/AppController.swift
    Tests/main.swift
)

echo "==> Compiling tests with swiftc"
swiftc \
    -target "$TARGET" \
    -sdk "$SDK_PATH" \
    -framework SwiftUI \
    -framework AppKit \
    "${SOURCES[@]}" \
    -o "$BIN"

echo "==> Running tests"
"$BIN"
