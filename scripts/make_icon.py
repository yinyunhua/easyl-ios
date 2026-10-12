#!/usr/bin/env python3
"""生成 1024x1024 应用图标（纯标准库，不依赖 Pillow）。"""
import os
import random
import struct
import zlib

SIZE = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

TOP = (79, 102, 245)      # 蓝紫渐变起点
BOTTOM = (168, 85, 247)   # 渐变终点
MODULES = 21              # 播放器图标用 21x21 方格

WHITE = b"\xff\xff\xff"


def build_matrix(seed=20250101):
    rng = random.Random(seed)
    n = MODULES
    matrix = [[0] * n for _ in range(n)]

    def finder(x0, y0):
        for y in range(7):
            for x in range(7):
                border = x in (0, 6) or y in (0, 6)
                center = 2 <= x <= 4 and 2 <= y <= 4
                matrix[y0 + y][x0 + x] = 1 if (border or center) else 0

    finder(0, 0)
    finder(n - 7, 0)
    finder(0, n - 7)

    reserved = set()
    for x0, y0 in ((0, 0), (n - 7, 0), (0, n - 7)):
        for y in range(-1, 8):
            for x in range(-1, 8):
                xx, yy = x0 + x, y0 + y
                if 0 <= xx < n and 0 <= yy < n:
                    reserved.add((xx, yy))

    for y in range(n):
        for x in range(n):
            if (x, y) not in reserved:
                matrix[y][x] = 1 if rng.random() < 0.46 else 0
    return matrix


def render(path):
    matrix = build_matrix()
    cell = int(SIZE * 0.68 / MODULES)
    qr_px = cell * MODULES
    origin = (SIZE - qr_px) // 2
    pad = max(1, cell // 9)

    rows = []
    for y in range(SIZE):
        t = y / (SIZE - 1)
        bg = bytes(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
        row = bytearray(bg * SIZE)

        gy = y - origin
        if 0 <= gy < qr_px and (gy % cell) >= pad:
            my = gy // cell
            for mx in range(MODULES):
                if matrix[my][mx]:
                    start = origin + mx * cell + pad
                    for gx in range(start, start + cell - pad):
                        offset = gx * 3
                        row[offset:offset + 3] = WHITE
        rows.append(bytes(row))

    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
           chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)
    print("icon written:", path, len(png), "bytes")


if __name__ == "__main__":
    render(OUT)
