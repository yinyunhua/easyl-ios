"""从 APK 提取的原始素材生成 iOS 资源：AppIcon 1024 + 品牌闪屏 + 闪屏锚点。

输入（_analysis/art 或 Resources 内的原始文件）：
  _analysis/art/ic_launcher_xxxhdpi.png  192x192 RGBA 应用图标
  Resources/splash_brand.webp            720x1280 品牌闪屏图

输出：
  Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
  Resources/splash_brand.png
  Resources/splash_anchor.json           闪屏内「logo 簇」的中心比例（供 SwiftUI 精确居中）
"""
import json
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "_analysis", "art")
RES = os.path.join(ROOT, "Resources")
ICON = os.path.join(RES, "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
ANCHOR = os.path.join(RES, "splash_anchor.json")

BG = (34, 36, 42)  # #22242A 与 Android 端窗口/WebView 背景一致

# 本素材实测：白色播放标中心 0.392，标+标题簇中心 0.470 → 偏移 +0.078
MARK_TO_CLUSTER_DY = 0.078


def make_icon():
    src = Image.open(os.path.join(ART, "ic_launcher_xxxhdpi.png")).convert("RGBA")
    src = src.resize((1024, 1024), Image.LANCZOS)
    flat = Image.new("RGB", (1024, 1024), BG)
    flat.paste(src, (0, 0), src)
    os.makedirs(os.path.dirname(ICON), exist_ok=True)
    flat.save(ICON, "PNG", optimize=True)
    print("icon:", ICON, flat.size)


def _bbox(pixels, w, h, pred, x0, x1, y0, y1):
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            r, g, b = pixels[x, y]
            if pred(r, g, b):
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    return (minx, miny, maxx, maxy) if maxx >= 0 else None


def measure_anchor(image):
    """测出闪屏里「白色播放标 + 黄色标题」簇的中心比例。

    该素材是满屏渐变图，logo 簇在设计稿里略高于几何中心；iOS 上按原图铺满会出现
    「看起来不居中」的观感，因此把锚点写进 JSON，由 SwiftUI 按锚点精确居中。

    白色播放标（圆角方框 + 三角）用「三通道都 >240」判定，稳定可靠；
    标题在黄色渐变背景上不易用颜色切分，因此用实测的「标→簇中心」固定纵向偏移换算
    （本素材实测：标中心 0.392、簇中心 0.470，偏移 +0.078）。
    """
    w, h = image.size
    px = image.load()
    mark = _bbox(px, w, h, lambda r, g, b: min(r, g, b) > 240,
                 int(0.2 * w), int(0.8 * w), int(0.2 * h), int(0.6 * h))
    if not mark:
        return {"contentCenterY": 0.47, "contentCenterX": 0.5, "detected": False}

    mark_center_y = ((mark[1] + mark[3]) / 2) / h
    mark_center_x = ((mark[0] + mark[2]) / 2) / w
    cluster_y = min(max(mark_center_y + MARK_TO_CLUSTER_DY, 0.30), 0.65)
    return {
        "contentCenterY": round(cluster_y, 4),
        "contentCenterX": round(mark_center_x, 4),
        "markCenterY": round(mark_center_y, 4),
        "sourceWidth": w,
        "sourceHeight": h,
        "detected": True,
    }


def make_splash():
    src = Image.open(os.path.join(RES, "splash_brand.webp")).convert("RGB")
    out = os.path.join(RES, "splash_brand.png")
    src.save(out, "PNG", optimize=True)
    anchor = measure_anchor(src)
    with open(ANCHOR, "w", encoding="utf-8") as fh:
        json.dump(anchor, fh, ensure_ascii=False, indent=2)
    print("splash:", out, src.size, "anchor:", anchor)


if __name__ == "__main__":
    make_icon()
    make_splash()
