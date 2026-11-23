#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `1.1/{cn,en,tr}` 里的手机截图转成 App Store 可上传尺寸 **1179×2556**（6.1 寸）。

为什么需要这一步：原始截图是 828×1792（iPhone 11 级 2x），而 ASC 的
「6.1 寸显示屏」槽位要求 1179×2556。两者比例几乎一样：

    828  / 1792 = 0.46205
    1179 / 2556 = 0.46127          ← 差 0.17%，肉眼不可见

所以做法是「先按高度放大到 2556，再把多出来的 1px 宽居中裁掉」，
**不拉伸、不变形**；放大 1.43× 后补一次轻度反锐化，避免小字发虚。

用法：
    python make_upload_sizes.py            # 转换 cn / en / tr 三个目录
    python make_upload_sizes.py cn         # 只转一个目录

输出：`1.1/<lang>/upload-1179x2556/*.png`（RGB、无透明通道、单张 < 8MB）
"""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from PIL import Image, ImageFilter

BASE = Path(__file__).resolve().parent          # docs/store-shots/1.1
OUT_DIR_NAME = "upload-1179x2556"
TARGET_W, TARGET_H = 1179, 2556
LANGS = ("cn", "en", "tr")

# 放大 1.43× 后会略软，补一次轻反锐化（数值偏保守，避免出现白边光晕）
SHARPEN = dict(radius=1.2, percent=55, threshold=2)


def convert(src: Path, dst: Path) -> tuple[int, int, int]:
    """转一张，返回 (输出宽, 输出高, 文件字节数)。"""
    with Image.open(src) as im:
        img = im.convert("RGB")                 # 去掉 alpha（ASC 不需要透明通道）

    scale = TARGET_H / img.height
    new_w = int(round(img.width * scale))
    resized = img.resize((new_w, TARGET_H), Image.LANCZOS)
    resized = resized.filter(ImageFilter.UnsharpMask(**SHARPEN))

    if new_w > TARGET_W:                        # 居中裁掉溢出的一两列
        left = (new_w - TARGET_W) // 2
        resized = resized.crop((left, 0, left + TARGET_W, TARGET_H))
    elif new_w < TARGET_W:                      # 理论上不会发生，留个兜底
        canvas = Image.new("RGB", (TARGET_W, TARGET_H), (0, 0, 0))
        canvas.paste(resized, ((TARGET_W - new_w) // 2, 0))
        resized = canvas

    # 与营销脚本同样的落盘方式：临时文件 + 原子替换 + 重试
    # （Windows 上杀软/缩略图索引会短暂占用刚写完的文件）
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    for attempt in range(5):
        try:
            resized.save(tmp, "PNG", optimize=True, compress_level=9)
            os.replace(tmp, dst)
            break
        except OSError as error:
            if attempt == 4:
                raise
            print(f"  retry {dst.name} ({error})")
            time.sleep(0.4)
    return resized.width, resized.height, dst.stat().st_size


def main(argv: list[str]) -> int:
    langs = [a for a in argv[1:] if a in LANGS] or list(LANGS)
    bad = 0
    total = 0
    for lang in langs:
        src_dir = BASE / lang
        if not src_dir.is_dir():
            print(f"跳过 {lang}：目录不存在")
            continue
        out_dir = src_dir / OUT_DIR_NAME
        out_dir.mkdir(exist_ok=True)
        files = sorted(p for p in src_dir.iterdir()
                       if p.is_file() and p.suffix.lower() == ".png")
        print(f"\n== {lang}：{len(files)} 张 ==")
        for src in files:
            dst = out_dir / f"{src.stem}.png"
            w, h, size = convert(src, dst)
            total += 1
            ok = (w, h) == (TARGET_W, TARGET_H) and size <= 8 * 1024 * 1024
            bad += 0 if ok else 1
            print(f"  {src.name:<14} -> {dst.name:<14} {w}x{h}  "
                  f"{size / 1024:.0f} KB  {'PASS' if ok else 'FAIL'}")
    print(f"\n{total - bad}/{total} passed（目标 {TARGET_W}x{TARGET_H}，单张 ≤8MB）")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
