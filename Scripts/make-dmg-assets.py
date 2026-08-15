#!/usr/bin/env python3
"""Renders the OriginCheck app icon and the DMG background image.

Pure Python (stdlib only: zlib + struct), so it runs on any machine. The
rendered PNGs are committed to assets/ so release builds never need to
render anything; this script exists so the artwork is reproducible.

Output:
  assets/AppIcon.png            1024x1024 app icon
  assets/dmg-background@2x.png  1320x920 DMG window background (2x)
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def write_png(path, width, height, pixel_fn):
    """pixel_fn(x, y) -> (r, g, b, a) with y measured from the top."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        for x in range(width):
            r, g, b, a = pixel_fn(x, y)
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", ihdr)
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)
    print(f"wrote {path} ({width}x{height})")


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3))


def dist_segment(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length_sq))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def rounded_rect(px, py, cx, cy, half_w, half_h, radius):
    """Signed distance to a rounded rect centered at (cx, cy)."""
    qx = abs(px - cx) - (half_w - radius)
    qy = abs(py - cy) - (half_h - radius)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - radius


def check_sdf(px, py, scale=1.0, origin=(0, 0)):
    """Signed distance to the OriginCheck checkmark (negative = inside)."""
    ox, oy = origin
    seg1 = dist_segment(px, py, ox + 350 * scale, oy + 545 * scale,
                        ox + 472 * scale, oy + 667 * scale)
    seg2 = dist_segment(px, py, ox + 472 * scale, oy + 667 * scale,
                        ox + 688 * scale, oy + 388 * scale)
    # Thick stroke: distance to the segment minus the half width.
    return min(seg1, seg2) - 59 * scale


# --- App icon ----------------------------------------------------------------

def icon_pixel(x, y, width, height):
    cx, cy = width / 2, height / 2
    r = 185
    d = rounded_rect(x, y, cx, cy, cx - r, cy - r, r)
    if d > 0:
        return (0, 0, 0, 0)

    # Vertical gradient: deep slate at the top, darker at the bottom.
    t = y / height
    base = mix((0x24, 0x32, 0x4F), (0x0E, 0x15, 0x26), t)

    # Soft inner highlight near the top edge.
    highlight = max(0.0, 1.0 - (y - 90) / 220.0) * 0.10
    base = mix(base, (0xFF, 0xFF, 0xFF), highlight * 0.5)

    # Inner border.
    border = rounded_rect(x, y, cx, cy, cx - 62, cy - 62, 128)
    if -8 < border < 0:
        base = mix(base, (0x8E, 0xA2, 0xC8), 0.55)

    # Checkmark: soft glow pass, then the solid core.
    check = check_sdf(x, y)
    if check < 160:
        glow_alpha = max(0.0, 1.0 - abs(check) / 160.0) * 0.35
        base = mix(base, (0x9F, 0xC7, 0xFF), glow_alpha)
    if check < 0:
        base = mix(base, (0xFF, 0xFF, 0xFF), 1.0)

    return tuple(int(max(0, min(255, v))) for v in base) + (255,)


# --- DMG background ----------------------------------------------------------

def background_pixel(x, y, width, height):
    t = y / height
    base = mix((0xF7, 0xF8, 0xFA), (0xE7, 0xEB, 0xF2), t)

    # Faint centered checkmark watermark.
    check = check_sdf(x, y, scale=2.1, origin=(-230, -140))
    if check < 260:
        alpha = max(0.0, 1.0 - abs(check) / 260.0)
        base = mix(base, (0x4A, 0x5E, 0x85), alpha * 0.16)

    # Thin frame, like a card edge.
    frame = rounded_rect(x, y, width / 2, height / 2,
                         width / 2 - 40, height / 2 - 40, 48)
    if -3 < frame < 0:
        base = mix(base, (0x4A, 0x5E, 0x85), 0.35)

    return tuple(int(max(0, min(255, v))) for v in base) + (255,)


def main():
    assets = os.path.join(ROOT, "assets")
    os.makedirs(assets, exist_ok=True)
    write_png(os.path.join(assets, "AppIcon.png"), 1024, 1024,
              lambda x, y: icon_pixel(x, y, 1024, 1024))
    write_png(os.path.join(assets, "dmg-background@2x.png"), 1320, 920,
              lambda x, y: background_pixel(x, y, 1320, 920))


if __name__ == "__main__":
    main()
