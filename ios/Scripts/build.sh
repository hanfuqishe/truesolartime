#!/usr/bin/env bash
# 在 macOS 上构建 iOS 版。需要完整 Xcode（Command Line Tools 不含 iOS SDK）。
# 用法：
#   bash ios/Scripts/build.sh                 # 构建模拟器产物
#   bash ios/Scripts/build.sh "platform=iOS Simulator,name=iPhone 16"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 不修改全局 xcode-select，直接用 DEVELOPER_DIR 指向 Xcode，无需 sudo。
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "错误：找不到可用的 Xcode（当前 $(xcode-select -p)）" >&2
    echo "请安装 Xcode 16.2 后重试；iOS SDK 只有完整 Xcode 才提供。" >&2
    exit 1
fi

if [ ! -d TrueSolarTime.xcodeproj ]; then
    if command -v xcodegen >/dev/null 2>&1; then
        echo "由 project.yml 生成工程 ..."
        xcodegen generate
    elif [ -x /tmp/xcodegen-dl/xcodegen/bin/xcodegen ]; then
        echo "由 project.yml 生成工程（使用已下载的 xcodegen）..."
        /tmp/xcodegen-dl/xcodegen/bin/xcodegen generate
    else
        echo "错误：缺少 TrueSolarTime.xcodeproj，且未安装 xcodegen" >&2
        echo "请先执行 brew install xcodegen && xcodegen generate，或按 README 手动建工程" >&2
        exit 1
    fi
fi

DESTINATION="${1:-generic/platform=iOS Simulator}"

echo "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
echo "构建目标：$DESTINATION"
xcodebuild \
    -project TrueSolarTime.xcodeproj \
    -scheme TrueSolarTime \
    -configuration Debug \
    -destination "$DESTINATION" \
    build