#!/usr/bin/env python3
"""Generate the flip2 default wallpaper: an anime-style dusk skyline with a
silhouetted figure, drawn procedurally so the asset is reproducible from this
script alone (no model checkpoint, no external image).

Native render is 642x428 — the wallpaper surface this ROM reports for the
240x320 panel under the 321x428 logical size override (dumpsys wallpaper:
``mWidth=642 mHeight=428``). Everything is drawn at 4x and downsampled, so
edges stay smooth without anti-alias hacks.

    python3 pipeline/wallpaper/gen-wallpaper.py --out pipeline/wallpaper/assets
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 642, 428
SS = 4  # supersample factor


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp(stops, t):
    """stops = [(pos, (r,g,b)), ...] ascending; t in 0..1."""
    if t <= stops[0][0]:
        return stops[0][1]
    for i in range(len(stops) - 1):
        p0, c0 = stops[i]
        p1, c1 = stops[i + 1]
        if t <= p1:
            f = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
            return lerp(c0, c1, f)
    return stops[-1][1]


def bez(p0, p1, p2, p3, n=48):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        out.append((x, y))
    return out


def taper(curve, w0, w1, cap="round"):
    """Widen a curve into a closed silhouette with tapering half-width."""
    left, right = [], []
    n = len(curve) - 1
    for i, (x, y) in enumerate(curve):
        if i == 0:
            tx, ty = curve[1][0] - x, curve[1][1] - y
        elif i == n:
            tx, ty = x - curve[i - 1][0], y - curve[i - 1][1]
        else:
            tx, ty = curve[i + 1][0] - curve[i - 1][0], curve[i + 1][1] - curve[i - 1][1]
        L = math.hypot(tx, ty) or 1.0
        nx, ny = -ty / L, tx / L
        w = w0 + (w1 - w0) * (i / n)
        left.append((x + nx * w, y + ny * w))
        right.append((x - nx * w, y - ny * w))
    poly = left + right[::-1]
    if cap == "round":
        poly += []
    return poly


def sky(img):
    px = np.zeros((H * SS, W * SS, 3), dtype=np.float32)
    stops = [
        (0.00, (16, 10, 38)),
        (0.22, (44, 20, 68)),
        (0.40, (104, 34, 92)),
        (0.55, (176, 54, 100)),
        (0.66, (240, 92, 86)),
        (0.74, (255, 154, 92)),
        (0.80, (255, 208, 142)),
        (0.83, (252, 226, 178)),
    ]
    hh = H * SS
    for y in range(hh):
        c = ramp(stops, y / (hh - 1))
        px[y, :, 0] = c[0]
        px[y, :, 1] = c[1]
        px[y, :, 2] = c[2]
    return px


def add_glow(arr, cx, cy, r, color, strength=1.0, power=2.2):
    hh, ww = arr.shape[:2]
    ys = np.arange(hh)[:, None]
    xs = np.arange(ww)[None, :]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / max(r, 1e-6)
    g = np.clip(1.0 - d, 0.0, 1.0) ** power * strength
    for i in range(3):
        arr[:, :, i] += g * color[i]
    return arr


def clouds(draw, rng):
    """Warm lens-shaped cloud bands near the horizon."""
    bands = [
        (0.44, 0.035, 0.30, 0.62, (255, 176, 150), 70),
        (0.52, 0.022, 0.55, 0.85, (255, 150, 140), 55),
        (0.60, 0.030, 0.10, 0.42, (255, 200, 160), 60),
        (0.68, 0.018, 0.62, 0.92, (255, 214, 170), 45),
        (0.36, 0.012, 0.70, 0.96, (214, 132, 150), 40),
    ]
    for yf, hf, x0f, x1f, col, a in bands:
        y = yf * H * SS
        h = hf * H * SS
        x0, x1 = x0f * W * SS, x1f * W * SS
        seg = 26
        pts_top, pts_bot = [], []
        for i in range(seg + 1):
            t = i / seg
            x = x0 + (x1 - x0) * t
            bulge = math.sin(math.pi * t) ** 0.7
            wob = 0.30 * math.sin(t * 9.0 + yf * 20) + 0.15 * math.sin(t * 23 + 1.7)
            th = h * (0.35 + 0.65 * bulge) * (1 + 0.18 * wob)
            pts_top.append((x, y - th * 0.55))
            pts_bot.append((x, y + th * 0.45))
        draw.polygon(pts_top + pts_bot[::-1], fill=col + (a,))


def horizon_and_sea(draw, arr):
    """Distant hills, then a calm sea that mirrors the sky colours."""
    hy = 0.795 * H * SS
    # hills, two depths
    for base, amp, col, seed in (
        (hy - 0.030 * H * SS, 0.030, (86, 40, 74), 0.0),
        (hy - 0.004 * H * SS, 0.016, (58, 26, 58), 1.9),
    ):
        pts = [(0, hy)]
        seg = 90
        for i in range(seg + 1):
            t = i / seg
            x = t * W * SS
            y = base - amp * H * SS * (
                0.55 * math.sin(t * 7.0 + seed) + 0.30 * math.sin(t * 17.0 + seed * 2.7) + 0.5
            )
            pts.append((x, y))
        pts.append((W * SS, hy))
        draw.polygon(pts, fill=col + (255,))

    # sea: gradient from the horizon colour down into deep violet
    top = int(hy)
    bottom = H * SS
    for y in range(top, bottom):
        f = (y - top) / max(1, bottom - top)
        c = ramp(
            [
                (0.0, (232, 128, 108)),
                (0.18, (150, 66, 96)),
                (0.55, (62, 30, 74)),
                (1.0, (22, 14, 40)),
            ],
            f,
        )
        draw.line([(0, y), (W * SS, y)], fill=c + (255,))

    # sun glitter path
    rng = np.random.default_rng(7)
    for i in range(160):
        f = i / 160
        y = top + f * (bottom - top) * 0.92
        spread = 0.02 * W * SS + f * 0.16 * W * SS
        cx = 0.42 * W * SS + rng.normal(0, spread * 0.35)
        ln = (2 + 16 * f) * (0.4 + rng.random())
        a = int(max(0, 150 * (1 - f) ** 1.4))
        draw.line(
            [(cx - ln, y), (cx + ln, y)],
            fill=(255, 218, 176, a),
            width=max(1, int(1 + 2 * f)),
        )


def figure(draw_mask, ox, oy, h):
    """Draw the girl silhouette into an 'L' mask. Local units: h = her height,
    feet at (0,0), head top near (0,-1). Facing left, hair streaming left."""
    def P(x, y):
        return (ox + x * h, oy + y * h)

    def poly(pts, shrink=1.0):
        draw_mask.polygon([P(x * shrink, y * shrink) for x, y in pts], fill=255)

    def ell(cx, cy, rx, ry):
        draw_mask.ellipse(
            [P(cx - rx, cy - ry)[0], P(cx - rx, cy - ry)[1],
             P(cx + rx, cy + ry)[0], P(cx + rx, cy + ry)[1]],
            fill=255,
        )

    # legs
    for cx, w0, w1, toe in ((-0.040, 0.030, 0.018, -0.052), (0.048, 0.032, 0.019, 0.062)):
        c = bez((cx, -0.360), (cx * 0.9, -0.20), (cx * 1.0, -0.08), (toe, 0.002), 30)
        poly(taper(c, w0, w1, "flat"))
        # shoe
        ell(toe + (-0.018 if cx < 0 else 0.012), -0.006, 0.036, 0.014)

    # skirt (flared, wind off the sea)
    skirt = [
        (-0.078, -0.560), (0.070, -0.560),
        (0.128, -0.470), (0.150, -0.392),
        (0.086, -0.404), (0.030, -0.372),
        (-0.036, -0.404), (-0.104, -0.380),
        (-0.132, -0.462),
    ]
    poly(skirt)

    # torso: shoulders -> waist
    torso = [
        (-0.086, -0.782), (-0.030, -0.800), (0.030, -0.800), (0.086, -0.780),
        (0.072, -0.690), (0.058, -0.600), (0.080, -0.556),
        (-0.080, -0.556), (-0.056, -0.606), (-0.070, -0.692),
    ]
    poly(torso)

    # neck + head
    poly([(-0.022, -0.800), (0.022, -0.800), (0.020, -0.838), (-0.020, -0.838)])
    ell(0.004, -0.888, 0.059, 0.069)

    # arms: left arm hangs with the hand tucked behind the hip, right arm
    # lifted a little as if holding the hair off her face
    la = bez((-0.082, -0.772), (-0.112, -0.700), (-0.104, -0.620), (-0.086, -0.566), 26)
    poly(taper(la, 0.028, 0.017, "flat"))
    ra = bez((0.084, -0.774), (0.118, -0.740), (0.128, -0.690), (0.106, -0.652), 26)
    poly(taper(ra, 0.026, 0.015, "flat"))
    ell(0.100, -0.652, 0.020, 0.017)  # hand

    # hair: back mass behind the head
    ell(-0.004, -0.884, 0.080, 0.086)

    # hair: the long fall streaming left, two overlapping locks
    upper = bez((-0.052, -0.952), (-0.210, -0.930), (-0.372, -0.840), (-0.486, -0.690), 40)
    lower = bez((-0.486, -0.690), (-0.372, -0.640), (-0.230, -0.612), (-0.086, -0.640), 40)
    inner = bez((-0.086, -0.640), (-0.070, -0.720), (-0.060, -0.800), (-0.060, -0.870), 24)
    lock1 = upper + lower + inner
    poly(lock1)

    upper2 = bez((-0.070, -0.930), (-0.250, -0.888), (-0.410, -0.780), (-0.512, -0.612), 40)
    lower2 = bez((-0.512, -0.612), (-0.396, -0.598), (-0.246, -0.586), (-0.096, -0.612), 40)
    poly(upper2 + lower2)

    # a fine forelock crossing the face
    fore = bez((-0.036, -0.952), (-0.090, -0.900), (-0.116, -0.856), (-0.150, -0.812), 24)
    poly(taper(fore, 0.016, 0.004, "flat"))

    # flyaway strands
    for ctrl, w in (
        (((-0.10, -0.900), (-0.30, -0.860), (-0.44, -0.800), (-0.545, -0.700)), 0.008),
        (((-0.12, -0.860), (-0.28, -0.808), (-0.40, -0.742), (-0.470, -0.640)), 0.006),
        (((-0.02, -0.940), (-0.16, -0.940), (-0.28, -0.910), (-0.372, -0.862)), 0.005),
    ):
        poly(taper(bez(*ctrl, 30), w, 0.0015, "flat"))


def rooftop(draw):
    """Foreground ledge she stands on, plus a railing at the right edge.
    Drawn into the 'L' silhouette mask, so fills are plain 255."""
    top = 0.900 * H * SS
    draw.rectangle([0, top, W * SS, H * SS], fill=255)
    base = 0.888 * H * SS
    draw.rectangle([0, base, 0.80 * W * SS, top + 2], fill=255)
    bar_y = 0.700 * H * SS
    draw.rectangle([0.795 * W * SS, bar_y, 0.812 * W * SS, top], fill=255)
    draw.rectangle([0.795 * W * SS, bar_y, W * SS, bar_y + 0.010 * H * SS], fill=255)
    for f in (0.845, 0.900, 0.955):
        draw.rectangle([f * W * SS, bar_y + 0.010 * H * SS, (f + 0.012) * W * SS, top], fill=255)


def birds(draw, rng):
    for cx, cy, s in ((0.20, 0.30, 1.0), (0.26, 0.265, 0.75), (0.30, 0.315, 0.6), (0.16, 0.34, 0.55)):
        x, y = cx * W * SS, cy * H * SS
        k = s * 0.010 * H * SS
        draw.line([(x - 2 * k, y - k), (x - k, y - 0.35 * k), (x, y - 0.15 * k)], fill=(38, 20, 44, 210), width=max(1, int(1.6 * SS * 0.6)))
        draw.line([(x, y - 0.15 * k), (x + k, y - 0.35 * k), (x + 2 * k, y - k)], fill=(38, 20, 44, 210), width=max(1, int(1.6 * SS * 0.6)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets"))
    ap.add_argument("--size", default="%dx%d" % (W, H))
    args = ap.parse_args()

    w, h = (int(v) for v in args.size.lower().split("x"))
    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(20261029)

    arr = sky(None)
    # sun disc + layered glow
    sun_x, sun_y = 0.42 * W * SS, 0.735 * H * SS
    sun_r = 0.072 * H * SS
    arr = add_glow(arr, sun_x, sun_y, sun_r * 7.5, (70, 34, 30), 1.0, 2.6)
    arr = add_glow(arr, sun_x, sun_y, sun_r * 2.6, (120, 62, 40), 1.0, 2.2)
    arr = add_glow(arr, sun_x, sun_y, sun_r * 1.35, (150, 96, 60), 1.0, 1.8)
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGB").convert("RGBA")

    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    clouds(od, rng)

    # sun disc sits over the glow, under the silhouettes
    od.ellipse(
        [sun_x - sun_r, sun_y - sun_r, sun_x + sun_r, sun_y + sun_r],
        fill=(255, 244, 210, 255),
    )
    od.ellipse(
        [sun_x - sun_r * 1.06, sun_y - sun_r * 1.06, sun_x + sun_r * 1.06, sun_y + sun_r * 1.06],
        outline=(255, 226, 168, 90),
        width=int(3 * SS),
    )
    horizon_and_sea(od, arr)

    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)

    # rooftop first so her feet sit on it
    fig_h = 0.560 * H * SS
    fig_x = 0.717 * W * SS
    fig_y = 0.902 * H * SS
    rooftop(md)
    figure(md, fig_x, fig_y, fig_h)

    # rim light: the sun is behind her left, so the warm edge is the left band
    shift = int(2.2 * SS)
    shifted = Image.new("L", img.size, 0)
    shifted.paste(mask, (shift, 0))
    rim = Image.fromarray(
        np.clip(np.asarray(mask, dtype=np.int16) - np.asarray(shifted, dtype=np.int16), 0, 255).astype(np.uint8)
    )
    rim = rim.filter(ImageFilter.GaussianBlur(0.8 * SS))
    rim_col = Image.new("RGBA", img.size, (255, 196, 138, 255))

    body_col = Image.new("RGBA", img.size, (14, 10, 26, 255))
    overlay.paste(body_col, (0, 0), mask)
    overlay.paste(rim_col, (0, 0), rim)

    # soft bloom around the sun, above the silhouette
    bloom = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bloom)
    bd.ellipse(
        [sun_x - sun_r * 3.2, sun_y - sun_r * 3.2, sun_x + sun_r * 3.2, sun_y + sun_r * 3.2],
        fill=(255, 208, 150, 34),
    )
    bloom = bloom.filter(ImageFilter.GaussianBlur(18 * SS))
    overlay = Image.alpha_composite(overlay, bloom)

    birds(od, rng)

    # bokeh embers
    bok = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bok)
    for _ in range(46):
        x = rng.uniform(0, W * SS)
        y = rng.uniform(0.18, 0.86) * H * SS
        r = rng.uniform(0.8, 3.4) * SS
        a = int(rng.uniform(16, 52))
        bd.ellipse([x - r, y - r, x + r, y + r], fill=(255, 220, 178, a))
    bok = bok.filter(ImageFilter.GaussianBlur(1.1 * SS))
    overlay = Image.alpha_composite(overlay, bok)

    img = Image.alpha_composite(img, overlay)
    img = img.convert("RGB")

    # downsample from 4x
    img = img.resize((W, H), Image.LANCZOS)
    if (w, h) != (W, H):
        img = img.resize((w, h), Image.LANCZOS)

    # vignette + fine grain
    a = np.asarray(img, dtype=np.float32)
    hh, ww = a.shape[:2]
    ys = np.arange(hh)[:, None] / (hh - 1)
    xs = np.arange(ww)[None, :] / (ww - 1)
    d = np.sqrt(((xs - 0.5) * 1.06) ** 2 + ((ys - 0.52) * 1.02) ** 2)
    vig = np.clip(1.0 - 0.62 * np.clip(d - 0.30, 0, None) ** 1.5, 0.55, 1.0)[..., None]
    a = a * vig
    grain = np.random.default_rng(11).normal(0, 2.0, a.shape[:2])[..., None]
    a = np.clip(a + grain, 0, 255).astype(np.uint8)
    img = Image.fromarray(a, "RGB")

    png = os.path.join(args.out, "flip2-wallpaper.png")
    jpg = os.path.join(args.out, "flip2-wallpaper.jpg")
    img.save(png, optimize=True)
    img.save(jpg, quality=92, subsampling=0, optimize=True)
    print("wrote %s (%d bytes) and %s (%d bytes) at %dx%d" % (
        png, os.path.getsize(png), jpg, os.path.getsize(jpg), w, h))


if __name__ == "__main__":
    main()
