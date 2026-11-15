#!/usr/bin/env bash
# 验证三语 .lproj 真的进了 iOS 包（App Store 上架前 / CI 出包后跑一次）
#
# 用法（macOS，仓库根目录）：
#   bash ios/Scripts/verify-localization-packaging.sh                 # 先在 DerivedData 里找 .app
#   bash ios/Scripts/verify-localization-packaging.sh path/to/TrueSolarTime.app
#
# 检查项：
#   1. .app 里存在 en.lproj / zh-Hans.lproj / zh-Hant.lproj 三个目录；
#   2. 每个目录里有 Localizable.strings（且非空）与 InfoPlist.strings；
#   3. Info.plist 的 CFBundleDevelopmentRegion 是 en（兜底语言）；
#   4. 报告每个 .lproj 的字符串表大小，便于确认没被 main bundle 之外的路径吃掉。
#
# 退出码：0 = 全过；1 = 有问题。

set -uo pipefail

LANGS=(en zh-Hans zh-Hant)
APP="${1:-}"

if [[ -z "$APP" ]]; then
    echo "未指定 .app，尝试在 DerivedData / build 目录里找…"
    APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 4 -name "TrueSolarTime.app" -type d 2>/dev/null | head -n 1)
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "找不到 TrueSolarTime.app。请先 xcodebuild build/archive，或把 .app 路径作为参数传进来。"
    exit 1
fi

echo "检查：$APP"
problems=0

for lang in "${LANGS[@]}"; do
    dir="$APP/$lang.lproj"
    if [[ ! -d "$dir" ]]; then
        echo "  ERROR 缺少 $lang.lproj"
        problems=$((problems + 1))
        continue
    fi
    for name in Localizable.strings InfoPlist.strings; do
        file="$dir/$name"
        if [[ ! -f "$file" ]]; then
            echo "  ERROR $lang.lproj 缺少 $name"
            problems=$((problems + 1))
        elif [[ ! -s "$file" ]]; then
            echo "  ERROR $lang.lproj/$name 是空文件"
            problems=$((problems + 1))
        fi
    done
    if [[ -f "$dir/Localizable.strings" ]]; then
        echo "  OK    $lang.lproj（Localizable.strings $(wc -c < "$dir/Localizable.strings" | tr -d ' ') 字节）"
    fi
done

dev_region=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDevelopmentRegion' "$APP/Info.plist" 2>/dev/null || echo "")
if [[ "$dev_region" != "en" ]]; then
    echo "  WARN  CFBundleDevelopmentRegion = '${dev_region:-（空）}'，期望 en（不影响功能，非英文系统会按英文兜底）"
fi

if [[ "$problems" -gt 0 ]]; then
    echo ""
    echo "失败：$problems 个问题。多半是 XcodeGen 没把 Resources/<lang>.lproj 当成资源 —— 检查 project.yml 的 sources 是否覆盖 TrueSolarTime 目录。"
    exit 1
fi

echo ""
echo "三语 .lproj 都在包里。"
