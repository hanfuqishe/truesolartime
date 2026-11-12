"""Generate the launcher icon PNGs (no third-party dependencies).

Draws a dark dial with a golden ring, twelve ticks (hour marks) and two hands,
so the icon reads as a sundial clock at small sizes.
"""

import math
import pathlib
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SIZE = 216

BACKGROUND = (13, 20, 36, 255)
RING = (245, 214, 138, 255)
HAND = (245, 214, 138, 255)
HAND_SECOND = (217, 83, 79, 255)
FACE = (22, 32, 58, 255)


def blend(base, color, alpha):
    return tuple(int(round(base[i] * (1 - alpha) + color[i] * alpha)) for i in range(3)) + (255,)


def draw():
    pixels = [[BACKGROUND for _ in range(SIZE)] for _ in range(SIZE)]
    center = (SIZE - 1) / 2.0
    radius = SIZE * 0.42
    ring_inner = radius - SIZE * 0.035

    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - center
            dy = y - center
            distance = math.hypot(dx, dy)
            if distance <= radius:
                pixels[y][x] = FACE
            if ring_inner <= distance <= radius:
                # 抗锯齿：在环的边缘做一像素过渡。
                edge = min(ring_inner - distance, distance - radius) if distance < ring_inner else 0
                alpha = 1.0 if distance < ring_inner else max(0.0, min(1.0, 1.0 + edge))
                pixels[y][x] = blend(BACKGROUND if distance > radius else FACE, RING, alpha)

    tick_outer = ring_inner - SIZE * 0.01
    tick_inner = tick_outer - SIZE * 0.07
    for index in range(12):
        angle = math.radians(index * 30 - 90)
        length = SIZE * 0.012 if index % 3 else SIZE * 0.02
        steps = int(tick_outer - tick_inner) + 1
        for step in range(steps):
            r = tick_outer - step
            thickness = length
            for offset in range(int(-thickness), int(thickness) + 1):
                x = int(round(center + math.cos(angle) * r - math.sin(angle) * offset))
                y = int(round(center + math.sin(angle) * r + math.cos(angle) * offset))
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    pixels[y][x] = HAND

    def draw_hand(angle_degrees, length, width, color):
        angle = math.radians(angle_degrees - 90)
        steps = int(length)
        for step in range(steps):
            r = step
            for offset in range(-width, width + 1):
                x = int(round(center + math.cos(angle) * r - math.sin(angle) * offset))
                y = int(round(center + math.sin(angle) * r + math.cos(angle) * offset))
                if 0 <= x < SIZE and 0 <= y < SIZE:
                    pixels[y][x] = color

    draw_hand(300, radius * 0.55, 2, HAND)
    draw_hand(30, radius * 0.78, 3, HAND)
    draw_hand(150, radius * 0.62, 1, HAND_SECOND)

    for y in range(SIZE):
        for x in range(SIZE):
            if math.hypot(x - center, y - center) < SIZE * 0.035:
                pixels[y][x] = HAND
    return pixels


def write_png(path, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for pixel in row:
            raw.extend(pixel)
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(tag, payload):
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"wrote {path} ({len(data)} bytes)")


pixels = draw()
write_png(ROOT / "AppScope/resources/base/media/app_icon.png", pixels)
write_png(ROOT / "entry/src/main/resources/base/media/app_icon.png", pixels)
