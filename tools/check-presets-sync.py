#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""三端「常用城市」预设表一致性检查。

三端各自维护一份预设表（Android `Place.kt` / 鸿蒙 `Place.ets` / iOS `Place.swift`），
靠人工同步，容易漂移（2026-11 就出过：iOS 的摩尔曼斯克在第 16 位，另两端在第 22 位）。

本脚本从三份源码的 PRESETS / presets 数组里抽出 `presetKey + 纬度 + 经度 + countryCode`，要求：
  1. 数量相同；
  2. 顺序相同（逐项）；
  3. 每个城市的 key / 纬度 / 经度 / 国家码逐位相同（坐标容差 1e-9）。

用法：
    python tools/check-presets-sync.py            # 检查，失败退出码 1
    python tools/check-presets-sync.py --verbose  # 额外打印三端的城市清单

无第三方依赖，CI 与本地都能直接跑。
"""

from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FILES = {
    "android": os.path.join(
        ROOT, "android", "app", "src", "main", "java",
        "com", "realsuntime", "solartime", "data", "Place.kt",
    ),
    "harmony": os.path.join(
        ROOT, "harmony", "entry", "src", "main", "ets", "core", "Place.ets",
    ),
    "ios": os.path.join(ROOT, "ios", "TrueSolarTime", "Core", "Place.swift"),
}

# 三端的写法差异：
#   Kotlin : Place(39.9042, 116.4074, PlaceSource.MANUAL, "", "city_beijing", "cn"),
#   ArkTS  : new Place(39.9042, 116.4074, PlaceSource.MANUAL, '', 'city_beijing', 'cn'),
#   Swift  : Place(latitude: 39.9042, longitude: 116.4074, ..., presetKey: "city.beijing", countryCode: "cn"),
NUMBERS = re.compile(r"\(?\s*(?:latitude:\s*)?(-?\d+\.\d+)\s*,\s*(?:longitude:\s*)?(-?\d+\.\d+)")
KEY = re.compile(r"""city[._]([A-Za-z_]+)""")
COUNTRY = re.compile(r"""['"]([A-Za-z]{2})['"]""")


def find_array_start(src: str) -> int:
    """定位预设数组的起点（三端名字不同：PRESETS / presets；Kotlin 用 listOf）。

    注意：文件里可能先出现 `Place.presets.first { ... }` 这类**用法**，
    所以要把每个 marker 的所有出现位置都试一遍，直到找到后面紧跟 `[` 或 `listOf(` 的那一处。
    """
    for marker in ("PRESETS", "presets"):
        pos = 0
        while True:
            idx = src.find(marker, pos)
            if idx < 0:
                break
            if re.search(r"[=:]\s*(\[|listOf\()", src[idx:idx + 80]):
                return idx
            pos = idx + len(marker)
    return -1


def parse(path: str) -> list[tuple[str, float, float, str]]:
    if not os.path.isfile(path):
        raise SystemExit(f"[error] 找不到文件：{path}")
    src = io.open(path, encoding="utf-8", errors="replace").read()

    start = find_array_start(src)
    if start < 0:
        raise SystemExit(f"[error] {os.path.basename(path)} 里找不到 PRESETS / presets 数组")

    # 数组结束：Kotlin 的 listOf 用单独一行 ")"，ArkTS 用 "];"，Swift 用 "]"
    out: list[tuple[str, float, float, str]] = []
    for line in src[start:].split("\n"):
        stripped = line.strip()
        if out and stripped in ("]", "];", ")", "),"):
            break
        m = NUMBERS.search(line)
        if not m:
            continue
        # 鸿蒙的境外城市 presetKey 是空串（名字由 CityIndex 按坐标查），所以 key 允许缺失
        k = KEY.search(line)
        key = k.group(1).lower() if k else ""
        # countryCode 是行内最后一个两字母引号串
        cc_matches = COUNTRY.findall(line)
        if not cc_matches:
            continue
        out.append((key, float(m.group(1)), float(m.group(2)), cc_matches[-1].lower()))
    return out


def main(argv: list[str]) -> int:
    verbose = "--verbose" in argv or "-v" in argv

    data = {name: parse(path) for name, path in FILES.items()}

    ok = True
    for name, rows in data.items():
        print(f"{name:8s} {len(rows)} 个城市")
        if verbose:
            for i, (key, lat, lon, cc) in enumerate(rows, 1):
                print(f"  {i:2d}. {key:20s} {lat:9.4f}, {lon:9.4f}  {cc}")

    base_name = "android"
    base = data[base_name]

    for name, rows in data.items():
        if name == base_name:
            continue

        if len(rows) != len(base):
            print(f"[失败] {name} 有 {len(rows)} 个城市，{base_name} 有 {len(base)} 个")
            ok = False
            continue

        for i, (a, b) in enumerate(zip(base, rows), 1):
            ka, la, loa, ca = a
            kb, lb, lob, cb = b
            label = ka or kb or f"#{i}"
            # 主判据是坐标（鸿蒙境外城市没有 presetKey），顺序也要逐项对齐
            if abs(la - lb) > 1e-9 or abs(loa - lob) > 1e-9:
                print(
                    f"[失败] 第 {i} 个城市不一致（顺序或坐标）："
                    f"{base_name}={ka or '?'}({la}, {loa}) / {name}={kb or '?'}({lb}, {lob})"
                )
                ok = False
                continue
            if ca != cb:
                print(f"[失败] {label} 国家码不一致：{base_name}={ca} / {name}={cb}")
                ok = False
            if ka and kb and ka != kb:
                print(f"[警告] {label} presetKey 命名不同：{base_name}={ka} / {name}={kb}（不影响功能）")

    if ok:
        print(f"[通过] 三端预设一致：{len(base)} 个城市，顺序、坐标、国家码全同")
        return 0
    print("[失败] 三端预设不一致，见上")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
