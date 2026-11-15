#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App Store 新版页面营销素材：标题图 / 搜索结果图 / 横版截屏占位。

全部由代码绘制（Pillow + Windows 系统字体），不使用任何外部素材。
用法：
    python make_marketing.py            # 生成 7 个 PNG 并自校验
    python make_marketing.py --verify   # 只校验已生成的文件

设计约定（与 App 一致）：
    夜间深蓝背景 #0B1220 -> #16203A，右上角金色径向光晕（<=12%）
    金色强调   #F5D68A      正文 #E8EDF7      次级文字 #9AA7BF
    截图统一放进圆角卡片（半径 0.04*卡片宽，白色 8% 描边 + 高斯模糊阴影）
"""

from __future__ import annotations

import argparse
import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------- 路径 / 常量
BASE = Path(__file__).resolve().parent          # docs/store-shots/marketing
SHOT_DIR = BASE.parent / "asc-6.1-final"
# 主视觉：01.png（香港，夜间主题，繁体界面）。换主图只改这三行：
SHOT_FILE = "01.png"
# 主截图里的真实数字（01.png：标准时间 19:26、真太阳时 19:18）
NUM_TRUE = "19:18"
NUM_STD = "19:26"

FONT_REG = Path(r"C:\Windows\Fonts\msyh.ttc")     # Microsoft YaHei 常规
FONT_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")  # Microsoft YaHei 粗体

BG_TOP = (11, 18, 32)      # #0B1220
BG_BOT = (22, 32, 58)      # #16203A
SEARCH_TOP = (7, 12, 22)   # 搜索图背景更暗
SEARCH_BOT = (16, 24, 42)
GOLD = (245, 214, 138)     # #F5D68A
BODY = (232, 237, 247)     # #E8EDF7
DIM = (154, 167, 191)      # #9AA7BF
DIV = (74, 86, 112)

SHOT_ASPECT = 2556 / 1179  # 截图 高/宽
# 裁切起点：自动扫描截图里「主卡片」（圆角大卡）的上边缘，再向上留 4px 极小留白，
# 这样卡片内容从主卡顶部干净开始，不会切出半截页头/页头残影。
# 需要人工指定时把 CROP_TOP_OVERRIDE 设为截图像素坐标（如 349），否则为 None 走自动检测。
CROP_TOP_OVERRIDE = None
CROP_PAD = 4

# 图内文案（一律繁体中文）
TXT_TITLE = "真太陽時時鐘"
TXT_TAGLINE = "即時定位顯示目前真太陽時"
TXT_BULLETS = "日出日落 · 上中天 · 逐時天氣 · 十二時辰"
TXT_SEARCH_NAME = "真太陽時時鐘"
TXT_SEARCH_LINE = "真太陽時 · 隨身時鐘"
TXT_SIDE_L = "真太陽時"
TXT_SIDE_R = "標準時間"

EXPECTED = {
    "title-5244x2950.png": (5244, 2950),
    "title-3840x1646.png": (3840, 1646),
    "search-5244x2950.png": (5244, 2950),
    "search-3840x2560.png": (3840, 2560),
    "search-1920x1280.png": (1920, 1280),
    "screenshot-2556x1179.png": (2556, 1179),
    "screenshot-2622x1206.png": (2622, 1206),
}

# ---------------------------------------------------------------- 基础工具


def mix(c0, c1, t):
    t = min(1.0, max(0.0, t))
    return tuple(round(a + (b - a) * t) for a, b in zip(c0, c1))


@lru_cache(maxsize=64)
def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONT_BOLD if bold else FONT_REG), max(8, int(size)))


def metrics(size: int, bold: bool = False):
    asc, desc = font(size, bold).getmetrics()
    return asc, desc


def text_width(text: str, size: int, bold: bool = False) -> float:
    return font(size, bold).getlength(text)


def fit_size(text: str, bold: bool, max_w: float, size: int, min_size: int = 10) -> int:
    """把字号缩到文字宽度不超过 max_w（保持原始字号优先）。"""
    size = int(size)
    while size > min_size and text_width(text, size, bold) > max_w:
        size = int(size * 0.97)
    return max(min_size, size)


def paste_clipped(canvas: Image.Image, im: Image.Image, xy, mask=None) -> None:
    """paste 到任意（可为负 / 出界）坐标，超出画布的部分自动裁掉。"""
    x, y = int(xy[0]), int(xy[1])
    cw, ch = canvas.size
    iw, ih = im.size
    sx0, sy0 = max(0, -x), max(0, -y)
    dx0, dy0 = max(0, x), max(0, y)
    w = min(iw - sx0, cw - dx0)
    h = min(ih - sy0, ch - dy0)
    if w <= 0 or h <= 0:
        return
    src = im.crop((sx0, sy0, sx0 + w, sy0 + h))
    m = mask.crop((sx0, sy0, sx0 + w, sy0 + h)) if mask is not None else None
    canvas.paste(src, (dx0, dy0), m)


def gradient(size, c0, c1, axis=(0.25, 0.75)) -> Image.Image:
    """用 64x64 小图做线性渐变再放大（快且平滑）。"""
    n = 64
    small = Image.new("RGB", (n, n))
    px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x / (n - 1)) * axis[0] + (y / (n - 1)) * axis[1]
            px[x, y] = mix(c0, c1, t)
    return small.resize(size, Image.BICUBIC)


def add_glow(img: Image.Image, center, radius: float, color, max_alpha: float) -> Image.Image:
    """右上角柔和的径向光晕（半径内 0 -> 边缘满，透明度上限 max_alpha）。"""
    r = int(radius)
    if r <= 2:
        return img
    grad = Image.radial_gradient("L").resize((r * 2, r * 2), Image.BICUBIC)
    grad = grad.point(lambda v: int(((1.0 - v / 255.0) ** 1.65) * max_alpha * 255))
    mask = Image.new("L", img.size, 0)
    paste_clipped(mask, grad, (center[0] - r, center[1] - r))
    img.paste(Image.new("RGB", img.size, color), (0, 0), mask)
    return img


def add_bloom(img: Image.Image, center, radius: float, color, max_alpha: float) -> Image.Image:
    """叠在画面最上层的光晕（screen 方式加光）。

    夜间截图与背景同色系时，背景层的光晕会被卡片挡住；这层很淡的加光让
    「右上角金色光晕」在实际画面里仍然可见（峰值仍 <= 12%）。
    """
    r = int(radius)
    if r <= 2:
        return img
    grad = Image.radial_gradient("L").resize((r * 2, r * 2), Image.BICUBIC)
    grad = grad.point(lambda v: int(((1.0 - v / 255.0) ** 1.65) * max_alpha * 255))
    mask = Image.new("L", img.size, 0)
    paste_clipped(mask, grad, (center[0] - r, center[1] - r))
    layer = Image.new("RGB", img.size, (0, 0, 0))
    layer.paste(Image.new("RGB", img.size, color), (0, 0), mask)
    return ImageChops.screen(img, layer)


def rounded_mask(size, radius: int, ss: int = 4) -> Image.Image:
    """超采样后缩小的圆角蒙版（边缘抗锯齿）。"""
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [-1, -1, w * ss, h * ss], radius=max(1, radius) * ss, fill=255
    )
    return big.resize((w, h), Image.LANCZOS)


def drop_shadow(canvas: Image.Image, box, radius: int, blur: float, strength: float):
    """在 canvas 上叠一层柔和的黑色阴影（box 为卡片矩形）。"""
    mask = Image.new("L", canvas.size, 0)
    dx = int(blur * 0.25)
    dy = int(blur * 0.55)
    ImageDraw.Draw(mask).rounded_rectangle(
        [box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy],
        radius=radius,
        fill=int(255 * strength),
    )
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    return Image.composite(Image.new("RGB", canvas.size, (0, 0, 0)), canvas, mask)


def paste_card(
    canvas: Image.Image,
    shot: Image.Image,
    card_w: int,
    right_x: int,
    y_top: int,
    radius_frac: float = 0.04,
    stroke_alpha: float = 0.08,
    shadow_frac: float = 0.010,
    shadow_strength: float = 0.62,
):
    """把截图缩放进圆角卡片（带 8% 白描边 + 高斯阴影），允许出血出界。"""
    card_w = int(card_w)
    card_h = int(round(card_w * SHOT_ASPECT))
    radius = max(8, int(round(radius_frac * card_w)))
    x0 = int(right_x) - card_w
    y0 = int(y_top)

    blur = max(6.0, shadow_frac * canvas.width)
    canvas = drop_shadow(canvas, (x0, y0, x0 + card_w, y0 + card_h), radius, blur, shadow_strength)

    body = shot.resize((card_w, card_h), Image.LANCZOS).convert("RGBA")
    body.putalpha(rounded_mask((card_w, card_h), radius))

    # 白色 8% 描边：inset 半个线宽，贴在内侧
    stroke_w = max(2, int(round(card_w * 0.0045)))
    overlay = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(
        [stroke_w / 2, stroke_w / 2, card_w - 1 - stroke_w / 2, card_h - 1 - stroke_w / 2],
        radius=max(1, radius - stroke_w // 2),
        outline=(255, 255, 255, int(round(255 * stroke_alpha))),
        width=stroke_w,
    )
    card = Image.alpha_composite(body, overlay)
    paste_clipped(canvas, card, (x0, y0), mask=card)
    return canvas, (x0, y0, card_w, card_h)


# ---------------------------------------------------------------- 卡片裁切检测


def detect_card_top(shot: Image.Image, start_frac: float = 0.05,
                    delta: int = 8, run: int = 3) -> int:
    """扫描截图，返回「主卡片」上边缘的 y（截图像素）。

    做法：从 start_frac 处开始逐行取 x∈[10%,90%] 的中位色（中位数对文字/图标稳健），
    与首行页面底色比较，连续 run 行色差 >= delta 即认定进入主卡片。
    """
    W, H = shot.size
    xs = list(range(int(W * 0.10), int(W * 0.90), 3))

    def row_median(y: int):
        vals = sorted(shot.getpixel((x, y)) for x in xs)
        return vals[len(vals) // 2]

    start = int(H * start_frac)
    bg = row_median(start)
    streak = 0
    for y in range(start, H):
        c = row_median(y)
        if max(abs(a - b) for a, b in zip(c, bg)) >= delta:
            streak += 1
            if streak >= run:
                return y - run + 1
        else:
            streak = 0
    return int(H * 0.13)


_CROP_CACHE: dict = {}


def crop_top_px() -> int:
    """裁切起点（截图像素），带缓存：主卡上沿 - CROP_PAD。"""
    if CROP_TOP_OVERRIDE is not None:
        return int(CROP_TOP_OVERRIDE)
    if "top" not in _CROP_CACHE:
        with Image.open(SHOT_DIR / SHOT_FILE) as im:
            shot = im.convert("RGB")
        top = detect_card_top(shot)
        _CROP_CACHE["top"] = max(0, top - CROP_PAD)
        _CROP_CACHE["h"] = shot.height
        _CROP_CACHE["edge"] = top
    return _CROP_CACHE["top"]


def crop_frac() -> float:
    """裁切起点占截图高度的比例。"""
    crop_top_px()
    return _CROP_CACHE["top"] / _CROP_CACHE["h"]


# ---------------------------------------------------------------- 文本排版


def draw_runs(draw: ImageDraw.ImageDraw, x: float, baseline: float, runs) -> float:
    """按 run 依次画同一行的多段文字（不同颜色 / 字重 / 字号）。"""
    for text, color, bold, size in runs:
        f = font(size, bold)
        draw.text((x, baseline), text, font=f, fill=color, anchor="ls")
        x += f.getlength(text)
    return x


def draw_block(draw: ImageDraw.ImageDraw, x: float, center_y: float, lines) -> tuple:
    """竖向排一条文字块（每行可含多 run），返回块的外接框 (l, t, r, b)。

    line: {"runs": [(text, color, bold, size)], "gap": 行后间距}
    或    {"bar": (w, h, color), "gap": 行后间距}
    """
    heights = []
    for ln in lines:
        if "bar" in ln:
            heights.append(ln["bar"][1])
        else:
            heights.append(max(metrics(r[3], r[2])[0] + metrics(r[3], r[2])[1] for r in ln["runs"]))
    total = sum(heights) + sum(ln.get("gap", 0) for ln in lines[:-1])
    y = center_y - total / 2
    top = y
    right = x
    for i, ln in enumerate(lines):
        if "bar" in ln:
            w, h, color = ln["bar"]
            draw.rectangle([x, y + h * 0.25, x + w, y + h * 0.25 + max(3, h * 0.3)], fill=color)
            right = max(right, x + w)
        else:
            asc = max(metrics(r[3], r[2])[0] for r in ln["runs"])
            right = max(right, draw_runs(draw, x, y + asc, ln["runs"]))
        y += heights[i] + (ln.get("gap", 0) if i < len(lines) - 1 else 0)
    return (x, top, right, y)


def draw_vertical(draw: ImageDraw.ImageDraw, cx: float, center_y: float,
                  text: str, size: int, color, gap_frac: float = 0.32,
                  bold: bool = False) -> None:
    """竖排小字：逐字居中自上而下排列。"""
    step = size * (1.0 + gap_frac)
    total = step * len(text) - size * gap_frac
    y = center_y - total / 2
    for ch in text:
        draw.text((cx, y + step / 2), ch, font=font(size, bold), fill=color, anchor="mm")
        y += step


# ---------------------------------------------------------------- 三种版式


def _check_bleed(box, H: int, tag: str, W: int) -> None:
    """确认卡片确实延伸到画布上下边缘（出血）且没有把底部留空。"""
    x0, y0, cw, ch = box
    if y0 + ch < H:
        print(f"  WARN {tag}: card bottom {y0 + ch} < canvas H {H}")
    if y0 > 0:
        print(f"  WARN {tag}: card top does not bleed (y0={y0})")
    if x0 < 0.5 * W:
        print(f"  WARN {tag}: card intrudes into left half (x0={x0})")


def _check_gap(bbox, box, margin: int, W: int, tag: str) -> None:
    """打印文案区与卡片的关系，确认左边距 >= 5%W 且文案不与卡片重叠。"""
    l, t, r, b = bbox
    x0 = box[0]
    print(f"  {tag}: text x={l}..{r:.0f} (left margin {l / W:.1%}W), "
          f"card x0={x0} ({x0 / W:.1%}W), gap {x0 - r:.0f}px")

    if l < 0.05 * W:
        print(f"  WARN {tag}: left margin {l / W:.1%}W < 5%W")
    if r > x0:
        print(f"  WARN {tag}: text overlaps card ({r:.0f} > {x0})")


def build_title(W: int, H: int, spec: dict) -> Image.Image:
    """标题图：夜间深蓝渐变 + 金色光晕，左文案 / 右截图卡片（出血）。"""
    canvas = gradient((W, H), BG_TOP, BG_BOT)
    add_glow(canvas, (int(W * 0.87), int(H * 0.08)), W * 0.55, GOLD, spec["glow"])

    shot = Image.open(SHOT_DIR / SHOT_FILE).convert("RGB")
    card_w = int(round(W * spec["card_w"]))
    canvas, box = paste_card(
        canvas, shot, card_w,
        right_x=int(W * 1.012), y_top=-int(round(crop_frac() * card_w * SHOT_ASPECT)),
        shadow_frac=0.008,
    )
    _check_bleed(box, H, "title", W)

    m = int(round(W * 0.060))
    zone = W * 0.42 - m
    t_size = fit_size(TXT_TITLE, True, zone, int(H * spec["title_h"]))
    tag_size = fit_size(TXT_TAGLINE, False, zone, int(H * spec["tag_h"]))
    num_size = int(H * spec["num_h"])
    while num_size > 10 and _num_width(num_size) > zone:
        num_size = int(num_size * 0.97)
    bul_size = fit_size(TXT_BULLETS, False, zone, int(H * spec["bul_h"]))

    lines = [
        {"bar": (int(W * 0.048), int(H * 0.006), GOLD), "gap": int(H * 0.030)},
        {"runs": [(TXT_TITLE, BODY, True, t_size)], "gap": int(H * 0.024)},
        {"runs": [(TXT_TAGLINE, DIM, False, tag_size)], "gap": int(H * 0.016)},
        {"runs": [
            ("真太陽時 ", DIM, False, num_size),
            (NUM_TRUE, GOLD, True, num_size),
            ("  ·  ", DIV, False, num_size),
            ("標準時間 ", DIM, False, num_size),
            (NUM_STD, BODY, True, num_size),
        ], "gap": int(H * 0.020)},
        {"runs": [(TXT_BULLETS, DIM, False, bul_size)], "gap": 0},
    ]
    bbox = draw_block(ImageDraw.Draw(canvas), m, H * 0.5, lines)
    _check_gap(bbox, box, m, W, "title")
    # 顶层柔光：夜间截图与背景同色系，背景层光晕被卡片挡住，这里补一层很淡的加光
    canvas = add_bloom(canvas, (int(W * 0.97), int(-H * 0.05)), W * 0.42, GOLD, 0.09)
    return canvas


def _num_width(size: int) -> float:
    return (text_width("真太陽時 ", size) + text_width(NUM_TRUE, size, True)
            + text_width("  ·  ", size) + text_width("標準時間 ", size)
            + text_width(NUM_STD, size, True))


def build_search(W: int, H: int, spec: dict) -> Image.Image:
    """搜索结果图：更暗背景 + 更简洁文案，左 1/3 名称，右 2/3 截图卡片。"""
    canvas = gradient((W, H), SEARCH_TOP, SEARCH_BOT)
    add_glow(canvas, (int(W * 0.88), int(H * 0.06)), W * 0.50, GOLD, spec["glow"])

    shot = Image.open(SHOT_DIR / SHOT_FILE).convert("RGB")
    card_w = int(round(W * spec["card_w"]))
    canvas, box = paste_card(
        canvas, shot, card_w,
        right_x=int(W * 1.010), y_top=-int(round(crop_frac() * card_w * SHOT_ASPECT)),
        shadow_frac=0.008,
    )
    _check_bleed(box, H, "search", W)

    m = int(round(W * 0.060))
    zone = W * 0.33 - m
    name_size = fit_size(TXT_SEARCH_NAME, True, zone, int(H * spec["name_h"]))
    line_size = fit_size(TXT_SEARCH_LINE, False, zone, int(H * spec["line_h"]))

    lines = [
        {"bar": (int(W * 0.040), int(H * 0.006), GOLD), "gap": int(H * 0.028)},
        {"runs": [(TXT_SEARCH_NAME, BODY, True, name_size)], "gap": int(H * 0.022)},
        {"runs": [(TXT_SEARCH_LINE, DIM, False, line_size)], "gap": 0},
    ]
    bbox = draw_block(ImageDraw.Draw(canvas), m, H * 0.5, lines)
    _check_gap(bbox, box, m, W, "search")
    canvas = add_bloom(canvas, (int(W * 0.97), int(-H * 0.05)), W * 0.42, GOLD, 0.06)
    return canvas


def build_screen(W: int, H: int) -> Image.Image:
    """横版截屏占位：同一张截图居中（不旋转不拉伸），两侧竖排小字填充留白。"""
    canvas = gradient((W, H), BG_TOP, BG_BOT)
    add_glow(canvas, (int(W * 0.5), int(-H * 0.35)), W * 0.45, GOLD, 0.06)

    shot = Image.open(SHOT_DIR / SHOT_FILE).convert("RGB")
    card_h = H * 0.84
    card_w = card_h / SHOT_ASPECT
    right_x = int(W / 2 + card_w / 2)
    canvas, _ = paste_card(
        canvas, shot, card_w,
        right_x=right_x, y_top=int(round((H - card_h) / 2)),
        shadow_frac=0.010, shadow_strength=0.70,
    )

    d = ImageDraw.Draw(canvas)
    side = max(20, int(H * 0.048))
    # 左「真太陽時」用金色（对应 App 里金色真太阳时数字），右「標準時間」用白色
    draw_vertical(d, W * 0.115, H * 0.5, TXT_SIDE_L, side, GOLD, gap_frac=0.22)
    draw_vertical(d, W * 0.885, H * 0.5, TXT_SIDE_R, side, BODY, gap_frac=0.22)
    return canvas


# ---------------------------------------------------------------- 参数与主流程

TITLE_SPECS = {
    (5244, 2950): dict(card_w=0.395, title_h=0.112, tag_h=0.0300, num_h=0.0360,
                       bul_h=0.0270, glow=0.12),
    (3840, 1646): dict(card_w=0.360, title_h=0.140, tag_h=0.0400, num_h=0.0470,
                       bul_h=0.0350, glow=0.12),
}

SEARCH_SPECS = {
    (5244, 2950): dict(card_w=0.360, name_h=0.082, line_h=0.0300, glow=0.08),
    # 3:2 与小尺寸画布更「方」，卡片要再放大一点，底部才能整块出血（圆角完全出画）
    (3840, 2560): dict(card_w=0.375, name_h=0.070, line_h=0.0300, glow=0.08),
    (1920, 1280): dict(card_w=0.375, name_h=0.070, line_h=0.0300, glow=0.08),
}


def build_all() -> None:
    for (W, H), spec in TITLE_SPECS.items():
        img = build_title(W, H, spec)
        _save(img, f"title-{W}x{H}.png")
    for (W, H), spec in SEARCH_SPECS.items():
        img = build_search(W, H, spec)
        _save(img, f"search-{W}x{H}.png")
    for name in ("screenshot-2556x1179.png", "screenshot-2622x1206.png"):
        W, H = EXPECTED[name]
        _save(build_screen(W, H), name)


def _save(img: Image.Image, name: str) -> None:
    path = BASE / name
    img.convert("RGB").save(path, "PNG", optimize=True, compress_level=9)
    print(f"  saved {name}  {img.width}x{img.height}")


def verify() -> int:
    print("\n== verify: actual pixel size / file size ==")
    print(f"{'file':<30}{'expected':>12}{'actual':>12}{'MB':>9}  result")
    bad = 0
    for name, (ew, eh) in EXPECTED.items():
        path = BASE / name
        if not path.exists():
            print(f"{name:<30}{'MISSING':>12}")
            bad += 1
            continue
        with Image.open(path) as im:
            w, h = im.size
        mb = path.stat().st_size / (1024 * 1024)
        ok = (w == ew and h == eh) and mb <= 8.0
        bad += 0 if ok else 1
        print(f"{name:<30}{f'{ew}x{eh}':>12}{f'{w}x{h}':>12}{mb:>9.2f}  {'PASS' if ok else 'FAIL'}")
    print(f"\n{len(EXPECTED) - bad}/{len(EXPECTED)} passed "
          f"(pixel-exact size, <= 8 MB)")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--verify", action="store_true", help="只校验已生成文件")
    args = ap.parse_args()
    if not args.verify:
        if not (SHOT_DIR / SHOT_FILE).exists():
            print(f"missing source screenshot: {SHOT_DIR / SHOT_FILE}", file=sys.stderr)
            return 2
        print(f"source screenshot: {SHOT_FILE} (true solar {NUM_TRUE} / standard {NUM_STD})")
        cf = crop_frac()
        print(f"card top edge: y={_CROP_CACHE['edge']} -> crop from y={_CROP_CACHE['top']} "
              f"({cf:.2%} of shot height)")
        build_all()
    return 1 if verify() else 0


if __name__ == "__main__":
    raise SystemExit(main())
