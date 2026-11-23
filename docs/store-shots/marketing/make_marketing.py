#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App Store 新版页面营销素材：标题图 / 搜索结果图 / 横版截屏占位。

全部由代码绘制（Pillow + Windows 系统字体），不使用任何外部素材。
用法：
    python make_marketing.py            # 生成 7 张 + 裁切预览图，并自校验
    python make_marketing.py --verify   # 只校验已生成的文件

版式原则（App Store 产品页 hero 会对标题图做**居中裁切**）：
    所有关键内容（文字 + 卡片）都落在画面**中间 60% 宽**以内，超宽那张收进中间 50%，
    即左右各留 20%/25% 纯背景，横裁后再窄也不会切掉字。
    构图改为居中对称：金色短横 → 主标题 → 读数行 → 副标 → 手机截图（居中偏下、出血到底边）。

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
# 裁切起点：自动扫描截图里「主卡片」（圆角大卡）的上边缘，再向上留 4px 极小留白。
# 需要人工指定时把 CROP_TOP_OVERRIDE 设为截图像素坐标（如 349），否则为 None 走自动检测。
CROP_TOP_OVERRIDE = None
CROP_PAD = 4

# 超宽标题图（2.33:1）以**首页大卡片为主体**：把卡片整块裁出来放大，而不是
# 从卡片上沿一直裁到屏幕底部（那样卡片只占 21% 宽，字看不清）。
# 自动检测的边界（01.png 实测）：x 56..1121、y 353..964 → 1066x611，高宽比 0.573。
# 需要人工指定时写 (x0, y0, x1, y1)（截图像素，右下开区间）。
CARD_BOX_OVERRIDE = None
# 裁进卡片内部一点，避开截图里自带的圆角与描边（否则贴到画布上会留一圈底色毛边）。
CARD_INSET = 8

# 图内文案（一律繁体中文）
# 英文版（用 docs/store-shots/1.1/en 的原生英文截图，828x1792）
SHOT_DIR_EN = BASE.parent / "1.1" / "en"
SHOT_FILE_EN = "IMG_0064.PNG"          # 纽约 · 夜间主题 · UTC-5，标准 23:05 vs 真太阳时 23:23
TXT_TITLE_EN = "True Solar Clock"
TXT_TAGLINE_EN = "Real solar time at your location"

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


def runs_width(runs) -> float:
    return sum(text_width(t, s, b) for t, _c, b, s in runs)


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


def _radial_mask(size, center, radius: float, max_alpha: float) -> Image.Image:
    r = int(radius)
    grad = Image.radial_gradient("L").resize((r * 2, r * 2), Image.BICUBIC)
    grad = grad.point(lambda v: int(((1.0 - v / 255.0) ** 1.65) * max_alpha * 255))
    mask = Image.new("L", size, 0)
    paste_clipped(mask, grad, (center[0] - r, center[1] - r))
    return mask


def add_glow(img: Image.Image, center, radius: float, color, max_alpha: float) -> Image.Image:
    """背景层柔和的径向光晕（中心最亮，透明度上限 max_alpha）。"""
    if int(radius) <= 2:
        return img
    mask = _radial_mask(img.size, center, radius, max_alpha)
    img.paste(Image.new("RGB", img.size, color), (0, 0), mask)
    return img


def add_bloom(img: Image.Image, center, radius: float, color, max_alpha: float) -> Image.Image:
    """叠在画面最上层的光晕（screen 方式加光）。

    夜间截图与背景同色系时，背景层的光晕会被卡片挡住；这层很淡的加光让
    「右上角金色光晕」在实际画面里仍然可见（峰值仍 <= 12%）。
    """
    if int(radius) <= 2:
        return img
    mask = _radial_mask(img.size, center, radius, max_alpha)
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
    center_x: int,
    y_top: int,
    radius_frac: float = 0.04,
    stroke_alpha: float = 0.08,
    shadow_frac: float = 0.010,
    shadow_strength: float = 0.62,
):
    """把截图放进居中圆角卡片（8% 白描边 + 高斯阴影），卡片可向下出血出界。

    card_h 由传入 shot 的宽高比决定（标题图传的是「已裁到主卡片上沿」的图，
    横版截屏传的是完整截图）。
    """
    card_w = int(card_w)
    card_h = int(round(card_w * shot.height / shot.width))
    radius = max(8, int(round(radius_frac * card_w)))
    x0 = int(center_x) - card_w // 2
    y0 = int(y_top)

    blur = max(6.0, shadow_frac * canvas.width)
    canvas = drop_shadow(canvas, (x0, y0, x0 + card_w, y0 + card_h), radius, blur, shadow_strength)

    body = shot.resize((card_w, card_h), Image.LANCZOS)
    # 放大倍数大时（英文素材 828x1792，卡片 732px 要放到 1690px ≈ 2.3×）文字会发虚，
    # 做一次轻度反锐化补偿；中文素材只有 1.6×，不需要（加了反而出光晕）。
    scale = card_w / max(1, shot.width)
    if scale > 1.8:
        body = body.filter(ImageFilter.UnsharpMask(radius=1.4, percent=70, threshold=3))
    body = body.convert("RGBA")
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


def card_shot() -> Image.Image:
    """主截图裁到主卡片上沿（含 4px 留白），供居中卡片使用。"""
    if "shot" not in _CROP_CACHE:
        with Image.open(SHOT_DIR / SHOT_FILE) as im:
            shot = im.convert("RGB")
        _CROP_CACHE["shot"] = shot.crop((0, crop_top_px(), shot.width, shot.height))
    return _CROP_CACHE["shot"]


def detect_card_box(shot: Image.Image) -> tuple:
    """扫描截图，返回「首页大卡片」整块的 (x0, y0, x1, y1)（右下开区间）。

    做法与 `detect_card_top()` 同源：按行/列取**中位色**（对文字与图标稳健），
    与页面底色比较，色差 >= 8 即认定在该行/列上；行方向要求连续 8 行回到底色才算卡片结束。
    """
    W, H = shot.size
    xs = list(range(int(W * 0.10), int(W * 0.90), 3))

    def med(vals):
        vals = sorted(vals)
        return vals[len(vals) // 2]

    bg = med([shot.getpixel((x, int(H * 0.095))) for x in xs])

    def delta(c):
        return max(abs(a - b) for a, b in zip(c, bg))

    top = None
    for y in range(int(H * 0.08), H):
        if delta(med([shot.getpixel((x, y)) for x in xs])) >= 8:
            top = y
            break
    if top is None:
        raise RuntimeError("没能定位卡片上沿")

    bottom = None
    run = 0
    for y in range(top + 10, H):
        if delta(med([shot.getpixel((x, y)) for x in xs])) < 8:
            run += 1
            if run >= 8:
                bottom = y - run
                break
        else:
            run = 0
    if bottom is None:
        raise RuntimeError("没能定位卡片下沿")

    ys = list(range(top + 20, bottom - 20, 3))

    def col_delta(x):
        return delta(med([shot.getpixel((x, y)) for y in ys]))

    left = next((x for x in range(W) if col_delta(x) >= 8), None)
    right = next((x for x in range(W - 1, -1, -1) if col_delta(x) >= 8), None)
    if left is None or right is None:
        raise RuntimeError("没能定位卡片左右边界")
    return (left, top, right + 1, bottom)


def card_box(shot_path: Path | None = None) -> tuple:
    """首页大卡片的截图像素边界（带缓存与内缩）。可传入另一张截图（英文版）。"""
    path = shot_path or (SHOT_DIR / SHOT_FILE)
    key = f"box::{path}"
    if CARD_BOX_OVERRIDE is not None and shot_path is None:
        return CARD_BOX_OVERRIDE
    if key not in _CROP_CACHE:
        with Image.open(path) as im:
            shot = im.convert("RGB")
        x0, y0, x1, y1 = detect_card_box(shot)
        _CROP_CACHE[f"raw::{path}"] = (x0, y0, x1, y1)
        _CROP_CACHE[key] = (x0 + CARD_INSET, y0 + CARD_INSET, x1 - CARD_INSET, y1 - CARD_INSET)
    return _CROP_CACHE[key]


def hero_card(shot_path: Path | None = None) -> Image.Image:
    """只裁出首页大卡片本身（不含标题栏、太阳圆盘、地图），供「卡片为主体」的标题图使用。"""
    path = shot_path or (SHOT_DIR / SHOT_FILE)
    key = f"hero::{path}"
    if key not in _CROP_CACHE:
        with Image.open(path) as im:
            shot = im.convert("RGB")
        _CROP_CACHE[key] = shot.crop(card_box(shot_path))
    return _CROP_CACHE[key]


# ---------------------------------------------------------------- 居中排版


def center_runs(draw: ImageDraw.ImageDraw, cx: float, cy: float, runs) -> tuple:
    """在 (cx, cy) 处水平+垂直居中画一行多 run 文字，返回其横坐标区间。"""
    asc = max(metrics(s, b)[0] for _t, _c, b, s in runs)
    desc = max(metrics(s, b)[1] for _t, _c, b, s in runs)
    total = runs_width(runs)
    x = cx - total / 2
    baseline = cy + (asc - desc) / 2
    x0 = x
    for text, color, bold, size in runs:
        f = font(size, bold)
        draw.text((x, baseline), text, font=f, fill=color, anchor="ls")
        x += f.getlength(text)
    return (x0, x)


def center_bar(draw: ImageDraw.ImageDraw, cx: float, cy: float,
               w: float, h: float, color) -> tuple:
    """居中金色短横。"""
    draw.rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=color)
    return (cx - w / 2, cx + w / 2)


def _safe_bounds(W: int, safe: float) -> tuple:
    """中间 safe 宽度的安全区边界（像素）。"""
    return (W * (0.5 - safe / 2), W * (0.5 + safe / 2))


def _report_safe(name: str, text_box, card_box, W: int, safe: float) -> None:
    """打印文字 / 卡片占画面宽度的区间，并校验是否落在中间安全区内。"""
    lo, hi = _safe_bounds(W, safe)
    t0, t1 = text_box
    c0, c1 = card_box
    inside = t0 >= lo and t1 <= hi and c0 >= lo and c1 <= hi
    print(f"  {name}: text {t0 / W:.1%}..{t1 / W:.1%}W   card {c0 / W:.1%}..{c1 / W:.1%}W"
          f"   safe ±{safe / 2:.0%} ({lo / W:.0%}..{hi / W:.0%}W)  "
          f"{'PASS' if inside else 'FAIL'}")
    if not inside:
        print(f"  WARN {name}: 内容超出居中安全区")


# ---------------------------------------------------------------- 三种版式


def build_title(W: int, H: int, spec: dict) -> Image.Image:
    """标题图：居中对称构图（文字在上、手机卡片居中偏下并向下出血）。"""
    canvas = gradient((W, H), BG_TOP, BG_BOT)
    add_glow(canvas, (int(W * 0.87), int(H * 0.06)), W * 0.42, GOLD, spec["glow"])

    shot = card_shot()
    card_w = int(round(W * spec["card_w"]))
    canvas, box = paste_card(
        canvas, shot, card_w,
        center_x=W // 2, y_top=int(round(H * spec["card_top"])),
        shadow_frac=0.008,
    )

    cx = W / 2
    d = ImageDraw.Draw(canvas)
    zone = W * spec["safe"] * 0.94          # 文字不贴满安全区
    t_size = fit_size(TXT_TITLE, True, zone, int(H * spec["title_h"]))
    num_size = int(H * spec["num_h"])
    while num_size > 10 and _num_width(num_size) > zone:
        num_size = int(num_size * 0.97)
    tag_size = fit_size(TXT_TAGLINE, False, zone, int(H * spec["tag_h"]))
    bul_size = fit_size(TXT_BULLETS, False, zone, int(H * spec["bul_h"]))

    text_box = [W, 0]
    for rect in (
        center_bar(d, cx, H * spec["bar_cy"], W * spec["bar_w"], H * spec["bar_h"], GOLD),
        center_runs(d, cx, H * spec["title_cy"], [(TXT_TITLE, BODY, True, t_size)]),
        center_runs(d, cx, H * spec["num_cy"], [
            ("真太陽時 ", DIM, False, num_size),
            (NUM_TRUE, GOLD, True, num_size),
            ("  ·  ", DIV, False, num_size),
            ("標準時間 ", DIM, False, num_size),
            (NUM_STD, BODY, True, num_size),
        ]),
        center_runs(d, cx, H * spec["tag_cy"], [(TXT_TAGLINE, DIM, False, tag_size)]),
        center_runs(d, cx, H * spec["bul_cy"], [(TXT_BULLETS, DIM, False, bul_size)]),
    ):
        text_box[0] = min(text_box[0], rect[0])
        text_box[1] = max(text_box[1], rect[1])

    # 顶层柔光：夜间截图与背景同色系，背景层光晕被卡片挡住，这里补一层很淡的加光
    canvas = add_bloom(canvas, (int(W * 0.97), int(-H * 0.05)), W * 0.42, GOLD, spec["bloom"])
    _report_safe(f"title {W}x{H}", text_box, (box[0], box[0] + box[2]), W, spec["safe"])
    return canvas


def _num_width(size: int) -> float:
    return (text_width("真太陽時 ", size) + text_width(NUM_TRUE, size, True)
            + text_width("  ·  ", size) + text_width("標準時間 ", size)
            + text_width(NUM_STD, size, True))


def build_title_card(W: int, H: int, spec: dict,
                     shot_path: Path | None = None,
                     title: str = TXT_TITLE,
                     tagline: str = TXT_TAGLINE) -> Image.Image:
    """标题图（超宽 2.33:1）：**首页大卡片为主体**。

    与 `build_title()` 的区别：
        · 卡片整块裁出（不裁到屏幕底部），占比从 21% 提到 36% 宽；
        · 文字只留「名称」在卡片上方 + 一句话在下方，读数行（19:18/19:26）不再重复
          —— 卡片里本来就看得清了，重复反而抢视线。
    安全区仍按中间 `safe` 宽校验：卡片与文字都不许越界。
    """
    canvas = gradient((W, H), BG_TOP, BG_BOT)
    add_glow(canvas, (int(W * 0.87), int(H * 0.05)), W * 0.42, GOLD, spec["glow"])

    card = hero_card(shot_path)
    card_w = int(round(W * spec["card_w"]))
    canvas, box = paste_card(
        canvas, card, card_w,
        center_x=W // 2, y_top=int(round(H * spec["card_top"])),
        shadow_frac=0.009, shadow_strength=0.66,
    )

    cx = W / 2
    d = ImageDraw.Draw(canvas)
    zone = W * spec["safe"] * 0.94
    t_size = fit_size(title, True, zone, int(H * spec["title_h"]))
    cap_size = fit_size(tagline, False, zone, int(H * spec["cap_h"]))

    text_box = [W, 0]
    rects = [
        center_runs(d, cx, H * spec["title_cy"], [(title, BODY, True, t_size)]),
        center_runs(d, cx, H * spec["cap_cy"], [(tagline, DIM, False, cap_size)]),
    ]
    if spec.get("bar", True):
        rects.insert(0, center_bar(d, cx, H * spec["bar_cy"], W * spec["bar_w"],
                                   H * spec["bar_h"], GOLD))
    for rect in rects:
        text_box[0] = min(text_box[0], rect[0])
        text_box[1] = max(text_box[1], rect[1])

    canvas = add_bloom(canvas, (int(W * 0.97), int(-H * 0.05)), W * 0.42, GOLD, spec["bloom"])
    _report_safe(f"title-card {W}x{H}", text_box, (box[0], box[0] + box[2]), W, spec["safe"])
    return canvas


def build_search(W: int, H: int, spec: dict) -> Image.Image:
    """搜索结果图：同样居中对称，但只留「名称 + 一句话」+ 手机卡片。"""
    canvas = gradient((W, H), SEARCH_TOP, SEARCH_BOT)
    add_glow(canvas, (int(W * 0.87), int(H * 0.05)), W * 0.40, GOLD, spec["glow"])

    shot = card_shot()
    card_w = int(round(W * spec["card_w"]))
    canvas, box = paste_card(
        canvas, shot, card_w,
        center_x=W // 2, y_top=int(round(H * spec["card_top"])),
        shadow_frac=0.008,
    )

    cx = W / 2
    d = ImageDraw.Draw(canvas)
    zone = W * spec["safe"] * 0.94
    name_size = fit_size(TXT_SEARCH_NAME, True, zone, int(H * spec["name_h"]))
    line_size = fit_size(TXT_SEARCH_LINE, False, zone, int(H * spec["line_h"]))

    text_box = [W, 0]
    for rect in (
        center_bar(d, cx, H * spec["bar_cy"], W * spec["bar_w"], H * spec["bar_h"], GOLD),
        center_runs(d, cx, H * spec["name_cy"], [(TXT_SEARCH_NAME, BODY, True, name_size)]),
        center_runs(d, cx, H * spec["line_cy"], [(TXT_SEARCH_LINE, DIM, False, line_size)]),
    ):
        text_box[0] = min(text_box[0], rect[0])
        text_box[1] = max(text_box[1], rect[1])

    canvas = add_bloom(canvas, (int(W * 0.97), int(-H * 0.05)), W * 0.42, GOLD, spec["bloom"])
    _report_safe(f"search {W}x{H}", text_box, (box[0], box[0] + box[2]), W, spec["safe"])
    return canvas


def draw_vertical(draw: ImageDraw.ImageDraw, cx: float, center_y: float,
                  text: str, size: int, color, gap_frac: float = 0.22,
                  bold: bool = False) -> None:
    """竖排小字：逐字居中自上而下排列。"""
    step = size * (1.0 + gap_frac)
    total = step * len(text) - size * gap_frac
    y = center_y - total / 2
    for ch in text:
        draw.text((cx, y + step / 2), ch, font=font(size, bold), fill=color, anchor="mm")
        y += step


def build_screen(W: int, H: int) -> Image.Image:
    """横版截屏占位：同一张截图完整居中（不旋转不拉伸），两侧竖排小字填充留白。"""
    canvas = gradient((W, H), BG_TOP, BG_BOT)
    add_glow(canvas, (int(W * 0.5), int(-H * 0.35)), W * 0.45, GOLD, 0.06)

    shot = Image.open(SHOT_DIR / SHOT_FILE).convert("RGB")
    card_h = H * 0.84
    card_w = card_h / SHOT_ASPECT
    canvas, _ = paste_card(
        canvas, shot, card_w,
        center_x=W // 2, y_top=int(round((H - card_h) / 2)),
        shadow_frac=0.010, shadow_strength=0.70,
    )

    d = ImageDraw.Draw(canvas)
    side = max(20, int(H * 0.048))
    # 左「真太陽時」用金色（对应 App 里金色真太阳时数字），右「標準時間」用白色
    draw_vertical(d, W * 0.115, H * 0.5, TXT_SIDE_L, side, GOLD)
    draw_vertical(d, W * 0.885, H * 0.5, TXT_SIDE_R, side, BODY)
    return canvas


# ---------------------------------------------------------------- 裁切模拟预览


PREVIEW_PANEL_H = 900


def _preview_dims() -> tuple:
    """裁切模拟预览图的尺寸（左侧完整图 + 右侧中间 60% 裁切图 + 标签行）。"""
    W, H = EXPECTED["title-5244x2950.png"]
    cw = round(W * 0.6)
    aw = round(W * PREVIEW_PANEL_H / H)
    bw = round(cw * PREVIEW_PANEL_H / H)
    margin = round(PREVIEW_PANEL_H * 0.04)
    gap = round(PREVIEW_PANEL_H * 0.05)
    label = round(PREVIEW_PANEL_H * 0.09)
    return (margin * 2 + aw + gap + bw, margin + PREVIEW_PANEL_H + label + margin // 2)


def build_preview() -> Image.Image:
    """并排展示：完整标题图（标出裁切边界）vs 按中间 60% 宽裁切后的效果（同高）。"""
    W, H = EXPECTED["title-5244x2950.png"]
    cw = round(W * 0.6)
    x0 = (W - cw) // 2

    with Image.open(BASE / "title-5244x2950.png") as im:
        full = im.convert("RGB")
    cropped = full.crop((x0, 0, x0 + cw, H))

    ph = PREVIEW_PANEL_H
    panel_a = full.resize((round(W * ph / H), ph), Image.LANCZOS)
    panel_b = cropped.resize((round(cw * ph / H), ph), Image.LANCZOS)

    margin = round(ph * 0.04)
    gap = round(ph * 0.05)
    label_h = round(ph * 0.09)
    total = (margin * 2 + panel_a.width + gap + panel_b.width,
             margin + ph + label_h + margin // 2)
    canvas = Image.new("RGB", total, (8, 12, 22))
    canvas.paste(panel_a, (margin, margin))
    canvas.paste(panel_b, (margin + panel_a.width + gap, margin))

    d = ImageDraw.Draw(canvas)
    fs = max(14, round(ph * 0.033))
    baseline = margin + ph + round(label_h * 0.55)
    d.text((margin, baseline), f"完整标题图  {W}x{H}（金线 = 裁切边界）",
           font=font(fs), fill=DIM, anchor="ls")
    d.text((margin + panel_a.width + gap, baseline),
           f"模拟居中裁切 60%  {cw}x{H}",
           font=font(fs), fill=GOLD, anchor="ls")

    # 左图：标出 20% / 80% 两条裁切边界；两张都加细描边
    line_color = (128, 116, 82)
    for frac in (0.2, 0.8):
        lx = margin + panel_a.width * frac
        d.line([lx, margin, lx, margin + ph], fill=line_color, width=max(1, round(ph * 0.0025)))
    for box in ((margin, margin, margin + panel_a.width, margin + ph),
                (margin + panel_a.width + gap, margin,
                 margin + panel_a.width + gap + panel_b.width, margin + ph)):
        d.rectangle(box, outline=(42, 54, 84), width=max(1, round(ph * 0.002)))
    return canvas


# ---------------------------------------------------------------- 参数与主流程

# card_top / *_cy 都是「占画布高度」的比例；card_w / bar_w 是「占画布宽度」的比例。
TITLE_SPECS = {
    # 16:9：文字全部落在中间 60% 内（实测 30% W 上下），卡片 26% W 居中
    (5244, 2950): dict(card_w=0.260, card_top=0.582, safe=0.60,
                       bar_cy=0.185, bar_w=0.050, bar_h=0.006,
                       title_cy=0.300, title_h=0.125,
                       num_cy=0.418, num_h=0.038,
                       tag_cy=0.474, tag_h=0.030,
                       bul_cy=0.520, bul_h=0.024,
                       glow=0.12, bloom=0.09),
    # 超宽 2.33:1：**以首页大卡片为主体**（layout="card"）。
    # 卡片按 36% 宽放大（源截图 1066px → 1382px，仅 1.3 倍，字仍锐），
    # 上下只留「名称」与一句话；读数在卡片里本来就清楚，不再重复。
    (3840, 1646): dict(layout="card", card_w=0.440, card_top=0.206, safe=0.50,
                       bar=False,
                       title_cy=0.112, title_h=0.100,
                       cap_cy=0.878, cap_h=0.040,
                       glow=0.12, bloom=0.09),
}

# 英文版标题图：版式与中文版完全一致（同一套比例），只换截图与文案。
# 输出文件名带 -en 后缀；尺寸与中文版同规格，都进 EXPECTED 做像素校验。
TITLE_EN_SPECS = {
    (3840, 1646): dict(TITLE_SPECS[(3840, 1646)], out="title-3840x1646-en.png",
                       shot_path=SHOT_DIR_EN / SHOT_FILE_EN,
                       title=TXT_TITLE_EN, tagline=TXT_TAGLINE_EN),
}

SEARCH_SPECS = {
    (5244, 2950): dict(card_w=0.260, card_top=0.470, safe=0.60,
                       bar_cy=0.190, bar_w=0.040, bar_h=0.006,
                       name_cy=0.262, name_h=0.105,
                       line_cy=0.360, line_h=0.032,
                       glow=0.08, bloom=0.06),
    (3840, 2560): dict(card_w=0.300, card_top=0.430, safe=0.60,
                       bar_cy=0.180, bar_w=0.040, bar_h=0.006,
                       name_cy=0.242, name_h=0.095,
                       line_cy=0.335, line_h=0.032,
                       glow=0.08, bloom=0.06),
    (1920, 1280): dict(card_w=0.300, card_top=0.430, safe=0.60,
                       bar_cy=0.180, bar_w=0.040, bar_h=0.006,
                       name_cy=0.242, name_h=0.095,
                       line_cy=0.335, line_h=0.032,
                       glow=0.08, bloom=0.06),
}

EXPECTED["title-3840x1646-en.png"] = (3840, 1646)
EXPECTED["preview-crop-simulation.png"] = _preview_dims()


def build_all(only: str | None = None) -> None:
    for (W, H), spec in TITLE_SPECS.items():
        name = f"title-{W}x{H}.png"
        if only and only != name:
            continue
        builder = build_title_card if spec.get("layout") == "card" else build_title
        _save(builder(W, H, spec), name)
    for (W, H), spec in TITLE_EN_SPECS.items():
        name = spec["out"]
        if only and only != name:
            continue
        _save(build_title_card(W, H, spec,
                               shot_path=spec["shot_path"],
                               title=spec["title"],
                               tagline=spec["tagline"]), name)
    if only:
        return
    for (W, H), spec in SEARCH_SPECS.items():
        img = build_search(W, H, spec)
        _save(img, f"search-{W}x{H}.png")
    for name in ("screenshot-2556x1179.png", "screenshot-2622x1206.png"):
        W, H = EXPECTED[name]
        _save(build_screen(W, H), name)
    _save(build_preview(), "preview-crop-simulation.png")


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
    ap.add_argument("--only", default=None,
                    help="只重新生成一张，例如 --only title-3840x1646.png（其余文件不动）")
    args = ap.parse_args()
    if not args.verify:
        if not (SHOT_DIR / SHOT_FILE).exists():
            print(f"missing source screenshot: {SHOT_DIR / SHOT_FILE}", file=sys.stderr)
            return 2
        print(f"source screenshot: {SHOT_FILE} (true solar {NUM_TRUE} / standard {NUM_STD})")
        cf = crop_frac()
        print(f"card top edge: y={_CROP_CACHE['edge']} -> crop from y={_CROP_CACHE['top']} "
              f"({cf:.2%} of shot height)")
        box = card_box()
        print(f"hero card box: x {box[0]}..{box[2] - 1}  y {box[1]}..{box[3] - 1}  "
              f"({box[2] - box[0]}x{box[3] - box[1]})")
        build_all(args.only)
    return 1 if verify() else 0


if __name__ == "__main__":
    raise SystemExit(main())
