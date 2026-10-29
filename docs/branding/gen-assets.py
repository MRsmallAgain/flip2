#!/usr/bin/env python3
"""Generate simple flip2 / wizard marketing PNGs (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

INK = (27, 31, 36)
BG = (247, 246, 242)
ACCENT = (11, 98, 196)
OK = (21, 122, 60)
WHITE = (255, 255, 255)
LINE = (216, 212, 202)


def flip_icon(draw, cx, cy, w, h, fill=ACCENT, stroke=INK):
    x0, y0 = cx - w // 2, cy - h // 2
    r = max(4, w // 8)
    draw.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=r, fill=fill, outline=stroke, width=max(1, w // 32))
    pad = w // 6
    draw.rounded_rectangle(
        [x0 + pad, y0 + pad + h // 8, x0 + w - pad, y0 + h - pad],
        radius=max(2, r // 2),
        fill=WHITE,
        outline=LINE,
        width=max(1, w // 48),
    )
    hy = y0 + h // 5
    draw.line([x0 + pad, hy, x0 + w - pad, hy], fill=stroke, width=max(1, w // 40))


def try_font(size):
    for name in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ):
        p = Path(name)
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def save_logo_square(size, path):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    flip_icon(d, size // 2, size // 2, int(size * 0.55), int(size * 0.72))
    im.save(path, "PNG")


def save_favicon(path):
    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    flip_icon(d, 16, 16, 18, 24)
    im.save(path, "PNG")


def save_og_wizard(path):
    w, h = 1200, 630
    im = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, 120], fill=WHITE)
    d.line([0, 120, w, 120], fill=LINE, width=2)
    flip_icon(d, 180, 280, 140, 200)
    title = try_font(52)
    sub = try_font(28)
    d.text((320, 200), "Flip 2 Linux setup wizard", fill=INK, font=title)
    d.text((320, 270), "Verify every download · Chrome on Linux · WebUSB", fill=(85, 85, 85), font=sub)
    steps = ["1 credits", "2 files", "3 udev", "4 connect", "5 install", "6 verify"]
    x = 320
    for i, s in enumerate(steps):
        pill_w = 100 + len(s) * 6
        col = ACCENT if i == 0 else WHITE
        fg = WHITE if i == 0 else (119, 119, 119)
        d.rounded_rectangle([x, 340, x + pill_w, 380], radius=18, fill=col, outline=LINE)
        d.text((x + 14, 348), s, fill=fg, font=try_font(22))
        x += pill_w + 8
    d.text((320, 430), "SAFETY.md · Release installer zip for conservative first setup", fill=OK, font=try_font(22))
    im.save(path, "PNG", optimize=True)


def save_github_social(path):
    w, h = 1280, 640
    im = Image.new("RGB", (w, h), INK)
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / h
        r = int(INK[0] + (ACCENT[0] - INK[0]) * t * 0.45)
        g = int(INK[1] + (ACCENT[1] - INK[1]) * t * 0.45)
        b = int(INK[2] + (ACCENT[2] - INK[2]) * t * 0.45)
        d.line([(0, y), (w, y)], fill=(r, g, b))
    flip_icon(d, 200, h // 2, 160, 220, fill=ACCENT, stroke=WHITE)
    d.text((400, 200), "flip2 toolkit", fill=WHITE, font=try_font(64))
    d.text((400, 290), "TCL Flip 2 · one zip · offline voice · custom launcher", fill=(200, 210, 220), font=try_font(32))
    d.text((400, 380), "Magisk installer · browser wizard · de-root friendly", fill=(180, 200, 255), font=try_font(26))
    im.save(path, "PNG", optimize=True)


def save_readme_banner(path):
    w, h = 1280, 320
    im = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8, h], fill=ACCENT)
    flip_icon(d, 120, h // 2, 100, 140)
    d.text((220, 90), "Flip2 toolkit", fill=INK, font=try_font(48))
    d.text((220, 160), "Browser setup wizard · Tier B installer · four deployment tiers", fill=(85, 85, 85), font=try_font(24))
    im.save(path, "PNG", optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    wizard_out = ROOT / "wizard" / "assets"
    wizard_out.mkdir(parents=True, exist_ok=True)
    save_favicon(wizard_out / "favicon-32.png")
    save_logo_square(180, wizard_out / "apple-touch-icon.png")
    save_logo_square(512, OUT / "logo-512.png")
    save_og_wizard(wizard_out / "og-wizard.png")
    save_github_social(OUT / "github-social-preview.png")
    save_readme_banner(OUT / "readme-banner.png")
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" fill="none">\n  <rect width="128" height="128" rx="24" fill="#f7f6f2"/>\n  <rect x="34" y="22" width="60" height="84" rx="8" fill="#0b62c4" stroke="#1b1f24" stroke-width="2"/>\n  <rect x="42" y="38" width="44" height="58" rx="4" fill="#fff" stroke="#d8d4ca"/>\n  <line x1="42" y1="34" x2="86" y2="34" stroke="#1b1f24" stroke-width="1.5"/>\n</svg>\n'
    (OUT / "logo.svg").write_text(svg, encoding="utf-8")
    (wizard_out / "logo.svg").write_text(svg, encoding="utf-8")
    print("Wrote:", OUT, wizard_out)


if __name__ == "__main__":
    main()
