#!/usr/bin/env bash
# 在 macOS 上直接校验 Core 里的算法移植是否与 Android 版一致，无需 Xcode。
# 用法：bash ios/Scripts/verify.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
OUT="$BUILD_DIR/verify"

echo "编译 $ROOT/TrueSolarTime/Core + Scripts/main.swift ..."
swiftc -O \
    "$ROOT"/TrueSolarTime/Core/*.swift \
    "$ROOT"/Scripts/main.swift \
    -o "$OUT"

"$OUT"
