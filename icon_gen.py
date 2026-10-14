#!/usr/bin/env python3
"""为 daidai-panel-fn 生成 fnOS 应用图标（纯标准库，无需 PIL）。

fnOS 图标规格（参考 fnOS开发者 Skill）：
  - ICON.PNG   : 64 x 64 px，单文件不超过 1024 KB，sRGB，正方形
  - ICON_256.PNG: 256 x 256 px

图形：圆角方形渐变底 + 白色大写 "D"（呆呆面板标志），兼顾 64px 下可辨识。
"""
import struct
import sys
import zlib

BRAND_TOP = (47, 123, 246)   # #2F7BF6
BRAND_BOT = (11, 42, 102)    # #0B2A66


def _rounded_rect_cover(x, y, m, r):
    """点 (x,y) 在 inset=m、圆角半径=r 的圆角方形内时的覆盖率(0/1)。"""
    if x < m or x > 1 - m or y < m or y > 1 - m:
        return 0.0
    cx = min(max(x, m + r), 1 - m - r)
    cy = min(max(y, m + r), 1 - m - r)
    dx, dy = x - cx, y - cy
    return 1.0 if dx * dx + dy * dy <= r * r else 0.0


def _in_circle(x, y, cx, cy, r):
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def _in_rounded_rect(x, y, m, r, w, h):
    # 简化：先做 inset 裁剪，再做圆角
    if x < m or x > 1 - m or y < m or y > 1 - m:
        return 0.0
    ix = min(max(x, m + r), 1 - m - r)
    iy = min(max(y, m + r), 1 - m - r)
    dx, dy = x - ix, y - iy
    if abs(dx) <= w and abs(dy) <= h:
        return 1.0
    return 0.0


def shade(x, y, m=0.055, r=0.235):
    """返回 (r,g,b,a)，a 0~1。"""
    bg = _rounded_rect_cover(x, y, m, r)
    if bg == 0:
        return (0, 0, 0, 0.0)

    # 竖向渐变：上 BRAND_TOP -> 下 BRAND_BOT，左上高光
    t = (y - m) / (1 - 2 * m)
    t = min(max(t, 0.0), 1.0)
    r_ = int(BRAND_TOP[0] + (BRAND_BOT[0] - BRAND_TOP[0]) * t)
    g_ = int(BRAND_TOP[1] + (BRAND_BOT[1] - BRAND_TOP[1]) * t)
    b_ = int(BRAND_TOP[2] + (BRAND_BOT[2] - BRAND_TOP[2]) * t)
    glow = max(0.0, 1.0 - (((x - 0.30) ** 2 + (y - 0.20) ** 2) ** 0.5) / 0.55)
    r_ = min(255, r_ + int(26 * glow))
    g_ = min(255, g_ + int(22 * glow))
    b_ = min(255, b_ + int(9 * glow))

    # 大写 D：左侧竖条(茎) + 右侧圆弧(弓)
    D_WHITE = (255, 255, 255, 1.0)
    stem = _in_rounded_rect(x, y, 0.0, 0.06, 0.22, 0.70)
    # 弓：右侧半圆，圆心近右端，顶部对齐茎的上方
    bowl = _in_circle(x, y, 0.72, 0.35, 0.36)
    if stem or bowl:
        return D_WHITE
    return (r_, g_, b_, 1.0)


def _render(size, ss=5):
    rows = []
    inv = 1.0 / (size * ss)
    for py in range(size):
        row = bytearray()
        for px in range(size):
            ar = ag = ab = aa = 0.0
            for sy in range(ss):
                fy = (py * ss + sy + 0.5) * inv
                for sx in range(ss):
                    fx = (px * ss + sx + 0.5) * inv
                    cr, cg, cb, ca = shade(fx, fy)
                    ar += cr * ca
                    ag += cg * ca
                    ab += cb * ca
                    aa += ca
            n = ss * ss
            alpha = aa / n
            if aa > 0:
                row += bytes((int(ar / aa), int(ag / aa), int(ab / aa), int(alpha * 255 + 0.5)))
            else:
                row += b"\x00\x00\x00\x00"
        rows.append(bytes(row))
    return rows


def _chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def write_png(path, size, rows):
    raw = b"".join(b"\x00" + r for r in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + _chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + _chunk(b"IDAT", zlib.compress(raw, 9))
           + _chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"  {path}  {size}x{size}  {len(png)} B")


if __name__ == "__main__":
    out = sys.argv[1]
    import os
    os.makedirs(out, exist_ok=True)
    for s in (64, 256):
        path = f"{out}/ICON.PNG" if s == 64 else f"{out}/ICON_256.PNG"
        write_png(path, s, _render(s))
