"""Render the True Solar Time app icon.

A tilted elliptical watch dial rendered with analytic 3D shading: the dial
plate is a circle seen at an angle (spun 45 deg in the picture plane), and the
hands pivot at the lower focus of the resulting ellipse.

Usage:
    python design/render_icon.py preview   # draft sheets for iteration
    python design/render_icon.py all       # write every shipping asset
"""

import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------------------------------------------------------------- helpers


def hexc(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-12), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _box_pass(a, r, axis):
    if r < 1:
        return a
    if axis == 1:
        a = a.T
    n = a.shape[0]
    pad = np.concatenate([np.repeat(a[:1], r, 0), a, np.repeat(a[-1:], r + 1, 0)], 0)
    c = np.cumsum(np.concatenate([np.zeros((1,) + a.shape[1:]), pad], 0), 0)
    out = (c[2 * r + 1:2 * r + 1 + n] - c[0:n]) / (2 * r + 1)
    return out if axis == 0 else out.T


def blur(a, sigma):
    if sigma <= 0.4:
        return a
    r = max(1, int(round(sigma * 0.85)))
    out = a
    for _ in range(3):
        out = _box_pass(_box_pass(out, r, 0), r, 1)
    return out


def over(dst, src_rgb, src_a):
    return dst * (1.0 - src_a[..., None]) + src_rgb * src_a[..., None]


# ---------------------------------------------------------------- geometry


class Plate:
    """Circle -> tilted ellipse mapping plus the 3D basis of the plate."""

    def __init__(self, semi_major, tilt_deg=41.0, spin_deg=-45.0):
        self.a = semi_major
        T = math.radians(tilt_deg)
        self.k = math.cos(T)
        self.s = math.sin(T)
        th = math.radians(spin_deg)
        self.ct, self.st = math.cos(th), math.sin(th)
        # screen = A . (p, q); plate radius 1 == semi major axis
        rot = np.array([[self.ct, -self.st], [self.st, self.ct]])
        self.A = self.a * rot @ np.diag([1.0, self.k])
        self.Ainv = np.linalg.inv(self.A)
        self.e_p = np.array([self.ct, self.st, 0.0])
        self.e_q = np.array([-self.k * self.st, self.k * self.ct, self.s])
        self.e_n = unit(np.cross(self.e_p, self.e_q))

    def plate_coords(self, U, V, shift=(0.0, 0.0)):
        u = U - shift[0]
        v = V - shift[1]
        return (self.Ainv[0, 0] * u + self.Ainv[0, 1] * v,
                self.Ainv[1, 0] * u + self.Ainv[1, 1] * v)

    def plate_angle_for_screen_dir(self, deg):
        """deg measured from +x with y pointing down (so -90 is straight up)."""
        target = np.array([math.cos(math.radians(deg)), math.sin(math.radians(deg))])
        phi = np.linspace(0, 2 * math.pi, 7200, endpoint=False)
        d = self.A @ np.vstack([np.cos(phi), np.sin(phi)])
        d /= np.linalg.norm(d, axis=0)
        return float(phi[int(np.argmax(d[0] * target[0] + d[1] * target[1]))])


# ---------------------------------------------------------------- palette

BG_TOP = hexc("#243254")
BG_BOT = hexc("#090E1C")
GLOW = hexc("#FFB347")
GOLD = hexc("#F2C06A")
GOLD_DARK = hexc("#9A6B2B")
IVORY = hexc("#F7F1E1")
IVORY_EDGE = hexc("#D6C9AC")
NAVY = hexc("#18203A")
NAVY_LIGHT = hexc("#3E5182")
AMBER = hexc("#FFB03A")
WHITE = np.ones(3)

LIGHT = unit([-0.55, -0.72, 0.62])
HALF = unit(LIGHT + np.array([0.0, 0.0, 1.0]))

DEFAULTS = dict(
    a=0.96,
    tilt_deg=41.0,
    spin_deg=-45.0,
    pivot_frac=0.42,
    center=(0.0, 0.0),
    face=0.880,
    tick_in=0.690,
    tick_out=0.812,
    hand_min=0.80,
    hand_hour=0.48,
    minute_deg=-90.0,
    hour_deg=-24.0,
    lift=0.030,
)


def shade(nrm, base, ambient=0.30, diffuse=0.80, spec=0.55, shin=42.0, spec_col=WHITE):
    lam = np.clip(nrm[..., 0] * LIGHT[0] + nrm[..., 1] * LIGHT[1] + nrm[..., 2] * LIGHT[2], 0, 1)
    sp = np.clip(nrm[..., 0] * HALF[0] + nrm[..., 1] * HALF[1] + nrm[..., 2] * HALF[2], 0, 1) ** shin
    return np.clip(base * (ambient + diffuse * lam[..., None]) + spec_col * spec * sp[..., None], 0, 1)


def background(n, shift=(0.16, 0.20), glow=0.20):
    x = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    X, Y = np.meshgrid(x, x)
    t = np.clip((Y + 1.0) / 2.0, 0, 1)[..., None]
    bg = BG_TOP * (1 - t) + BG_BOT * t
    g = np.exp(-(((X + shift[0]) ** 2 + (Y + shift[1]) ** 2) / 0.72))
    bg = np.clip(bg + GLOW * glow * g[..., None], 0, 1)
    bg = bg * (1.0 - 0.28 * np.clip(np.hypot(X, Y) / 1.35, 0, 1) ** 2)[..., None]
    return np.clip(bg, 0, 1)


def render(n=1024, with_bg=True, **kw):
    c = dict(DEFAULTS)
    c.update(kw)
    pl = Plate(c["a"], c["tilt_deg"], c["spin_deg"])

    x = (np.arange(n) + 0.5) / n * 2.0 - 1.0
    X, Y = np.meshgrid(x, x)
    aa = 2.0 / (n * c["a"] * pl.k) * 1.1

    P, Q = pl.plate_coords(X, Y, shift=c["center"])
    r = np.hypot(P, Q)
    ang = np.arctan2(Q, P)
    face = c["face"]
    ctr = c["center"]

    def basis(nx, ny, nz):
        nrm = nx[..., None] * pl.e_p + ny[..., None] * pl.e_q + nz[..., None] * pl.e_n
        return nrm / np.maximum(np.linalg.norm(nrm, axis=-1, keepdims=True), 1e-9)

    canvas = background(n) if with_bg else np.zeros((n, n, 3))

    # --- drop shadow of the plate
    sp_, sq_ = pl.plate_coords(X, Y, shift=(ctr[0] + 0.045, ctr[1] + 0.075))
    shadow = (1.0 - smoothstep(1.0 - aa * 2, 1.0 + aa * 3, np.hypot(sp_, sq_))) * 0.62
    shadow = blur(shadow, n * 0.017)
    canvas = over(canvas, np.zeros(3), shadow)

    # --- bezel ring (torus cross-section) and dial face
    m_dial = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r)
    m_face = 1.0 - smoothstep(face - aa, face + aa, r)

    rc = (1.0 + face) / 2.0
    tr = (1.0 - face) / 2.0
    s_t = np.clip((r - rc) / tr, -1.0, 1.0)
    nz = np.sqrt(np.maximum(0.0, 1.0 - s_t ** 2))
    nrm_bezel = basis(s_t * np.cos(ang), s_t * np.sin(ang), nz)
    gold = 0.55 * GOLD + 0.45 * GOLD_DARK * (1.0 - nz[..., None]) ** 0.9
    bezel = shade(nrm_bezel, gold, ambient=0.30, diffuse=0.86, spec=0.72, shin=26.0,
                  spec_col=np.array([1.0, 0.96, 0.88]))
    bezel = np.clip(bezel * (0.55 + 0.45 * nz[..., None]), 0, 0.985)

    rr = np.clip(r / face, 0, 1)
    ivory = IVORY + (IVORY_EDGE - IVORY) * (rr ** 2.4)[..., None]
    ivory = ivory * (1.0 - 0.10 * rr ** 2)[..., None]
    ivory = ivory * (1.0 - 0.34 * np.exp(-((r - face) / 0.055) ** 2))[..., None]
    ivory = ivory * (1.0 - 0.09 * np.clip(P * 0.6 + Q * 0.8, -1, 1))[..., None]
    ivory = np.clip(ivory + GLOW * 0.045 * (1 - rr)[..., None], 0, 1)

    dial = ivory * m_face[..., None] + bezel * (1 - m_face)[..., None]

    # --- hour ticks: segments on rays from the pivot, hugging the rim, so the
    # scale always points at the hands' centre
    face_r = c["face"]
    pivot = (-c["pivot_frac"] * pl.s, 0.0)
    dp0 = P - pivot[0]
    dp1 = Q - pivot[1]
    rp = np.hypot(dp0, dp1)
    ap = np.arctan2(dp1, dp0)
    off = math.hypot(pivot[0], pivot[1])
    phi12 = pl.plate_angle_for_screen_dir(-90.0)
    for i in range(12):
        phi = phi12 + i * math.pi / 6.0
        major = i % 3 == 0
        b = pivot[0] * math.cos(phi) + pivot[1] * math.sin(phi)
        D = -b + math.sqrt(max(b * b + face_r * face_r - off * off, 0.0))
        # normalise by the local foreshortening so every tick reads equally long
        scale = float(np.hypot(*pl.A.dot([math.cos(phi), math.sin(phi)]))) / pl.a
        r2 = D - 0.045
        r1 = r2 - (0.120 if major else 0.082) / max(scale, 1e-3)
        hw = (0.030 if major else 0.0145) * scale / pl.k
        dphi = np.abs(np.arctan2(np.sin(ap - phi), np.cos(ap - phi)))
        band = smoothstep(r1 - aa, r1 + aa, rp) * (1.0 - smoothstep(r2 - aa, r2 + aa, rp))
        across = 1.0 - smoothstep(hw - aa, hw + aa, dphi * rp)
        m = band * across * m_face
        nrm = basis(0.42 * math.cos(phi) + np.zeros_like(r), 0.42 * math.sin(phi) + np.zeros_like(r),
                    np.ones_like(r))
        dial = over(dial, shade(nrm, NAVY, ambient=0.62, diffuse=0.45, spec=0.25, shin=30.0), m)

    # --- hands
    pivot = (-c["pivot_frac"] * pl.s, 0.0)
    lift = (pl.e_n[0] * c["lift"] + ctr[0], pl.e_n[1] * c["lift"] + ctr[1])

    def hand_shape(screen_deg, length, w0, tail, w_tail, grow=0.0, shift=lift):
        phi = pl.plate_angle_for_screen_dir(screen_deg)
        d = np.array([math.cos(phi), math.sin(phi)])
        p, q = pl.plate_coords(X, Y, shift)
        dp0, dp1 = p - pivot[0], q - pivot[1]
        u = dp0 * d[0] + dp1 * d[1]
        v = -dp0 * d[1] + dp1 * d[0]
        L = length + grow
        t = np.clip(u / L, 0, 1)
        w = w0 * (1.0 - t) ** 0.62 + 0.010 + grow
        main = ((1.0 - smoothstep(w - aa, w + aa, np.abs(v)))
                * (1.0 - smoothstep(L - aa * 2, L + aa * 2, u))
                * smoothstep(-aa, aa, u))
        T = tail + grow
        tw = w_tail * np.clip(1.0 + u / max(T, 1e-6), 0, 1) ** 0.7 + 0.010 + grow
        tl = ((1.0 - smoothstep(tw - aa, tw + aa, np.abs(v)))
              * smoothstep(-T - aa, -T + aa, u)
              * (1.0 - smoothstep(-aa, aa, u)))
        return np.maximum(main, tl) * m_face, u, v, w, d

    specs = [(c["minute_deg"], c["hand_min"], 0.041, 0.15, 0.032),
             (c["hour_deg"], c["hand_hour"], 0.057, 0.12, 0.043)]
    shapes = [hand_shape(*sp) for sp in specs]

    sm = blur(np.maximum.reduce([s[0] for s in shapes]), n * 0.011)
    sm = np.roll(np.roll(sm, int(n * 0.020), axis=0), int(n * 0.013), axis=1)
    dial = over(dial, np.array([0.10, 0.08, 0.06]), np.clip(sm, 0, 0.45) * m_face)

    for (sp, (m, u, v, w, d)) in zip(specs, shapes):
        rim, _, _, _, _ = hand_shape(*sp, grow=0.004)
        dial = over(dial, np.broadcast_to(NAVY * 0.80, (n, n, 3)), rim * 0.95)
        ratio = np.clip(v / (w + 1e-6), -1, 1)
        nrm = basis(0.72 * ratio * -d[1], 0.72 * ratio * d[0], np.ones_like(r))
        dial = over(dial, shade(nrm, NAVY_LIGHT, ambient=0.44, diffuse=0.66, spec=0.40, shin=34.0), m)
        ridge = (1.0 - smoothstep(0.06, 0.20, np.abs(ratio))) * m
        dial = over(dial, np.array([0.70, 0.74, 0.84]), ridge * 0.20)

    # --- hub
    hp = np.hypot(P - pivot[0], Q - pivot[1])
    rh = 0.074
    collar = ((1.0 - smoothstep(rh * 1.10, rh * 1.34, hp)) * smoothstep(rh * 0.98, rh * 1.12, hp))
    dial = over(dial, np.array([0.12, 0.10, 0.07]), collar * 0.45 * m_face)
    mh = 1.0 - smoothstep(rh - aa, rh + aa, hp)
    nz_h = np.sqrt(np.maximum(0.0, 1.0 - np.clip(hp / rh, 0, 1) ** 2))
    nrm_h = basis((P - pivot[0]) / rh, (Q - pivot[1]) / rh, nz_h + 0.02)
    dial = over(dial, shade(nrm_h, AMBER, ambient=0.34, diffuse=0.84, spec=0.95, shin=30.0), mh)

    # --- glass sheen near the upper-left of the face
    sheen = ((smoothstep(0.42, 0.66, rr) * (1.0 - smoothstep(0.78, 0.95, rr)))
             * np.clip(np.cos(ang - math.radians(268.0)), 0, 1) ** 3)
    sheen = blur(sheen, n * 0.012) * 0.10 * m_face
    dial = over(dial, WHITE, np.clip(sheen, 0, 1))

    if with_bg:
        out = over(canvas, dial, m_dial)
        return np.dstack([np.clip(out, 0, 1), np.ones((n, n))])

    out = over(np.zeros((n, n, 3)), dial, m_dial)
    return np.dstack([np.clip(out, 0, 1), np.clip(m_dial + shadow, 0, 1)])


# ---------------------------------------------------------------- outputs


def save(arr, path, size=None):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8))
    if size and size != img.width:
        img = img.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    return path


def preview():
    out = os.path.join(ROOT, "design", "drafts")
    variants = {
        "p35": dict(pivot_frac=0.35),
        "p45": dict(pivot_frac=0.45),
        "p60": dict(pivot_frac=0.60),
    }
    for name, kw in variants.items():
        arr = render(n=880, **kw)
        save(arr, os.path.join(out, name + ".png"))
        save(arr, os.path.join(out, name + "-96.png"), 96)
        print("wrote", name)


def shipping():
    full = render(n=2048)
    save(full, os.path.join(ROOT, "design", "icon-1024.png"), 1024)
    save(full, os.path.join(ROOT, "design", "icon-512.png"), 512)
    print("wrote store icons")

    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    for d, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        save(full, os.path.join(res, "mipmap-" + d, "ic_launcher.png"), px)
    print("wrote legacy mipmaps")

    fg = render(n=2048, a=0.68, with_bg=False)
    bg = background(2048, shift=(0.10, 0.14), glow=0.22)
    bg = np.dstack([bg, np.ones((2048, 2048))])
    for d, px in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)):
        save(fg, os.path.join(res, "mipmap-" + d, "ic_launcher_foreground.png"), px)
        save(bg, os.path.join(res, "mipmap-" + d, "ic_launcher_background.png"), px)
    print("wrote adaptive layers")

    ios_png = os.path.join(ROOT, "ios", "TrueSolarTime", "Assets.xcassets",
                           "AppIcon.appiconset", "icon-1024.png")
    flat = Image.fromarray((np.clip(full, 0, 1) * 255 + 0.5).astype(np.uint8)).convert("RGB")
    flat.resize((1024, 1024), Image.LANCZOS).save(ios_png, optimize=True)
    print("wrote ios icon (opaque)")


if __name__ == "__main__":
    (preview if (len(sys.argv) < 2 or sys.argv[1] == "preview") else shipping)()
