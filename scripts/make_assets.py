"""从 APK 提取的原始素材生成 iOS 资源：AppIcon 1024 + 品牌闪屏。

输入（_analysis/art 或 Resources 内的原始文件）：
  _analysis/art/ic_launcher_xxxhdpi.png  192x192 RGBA 应用图标
  Resources/splash_brand.webp            720x1280 品牌闪屏图

输出：
  Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
  Resources/splash_brand.png
"""
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "_analysis", "art")
RES = os.path.join(ROOT, "Resources")
ICON = os.path.join(RES, "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

BG = (34, 36, 42)  # #22242A 与 Android 端窗口/WebView 背景一致


def make_icon():
    src = Image.open(os.path.join(ART, "ic_launcher_xxxhdpi.png")).convert("RGBA")
    src = src.resize((1024, 1024), Image.LANCZOS)
    flat = Image.new("RGB", (1024, 1024), BG)
    flat.paste(src, (0, 0), src)
    os.makedirs(os.path.dirname(ICON), exist_ok=True)
    flat.save(ICON, "PNG", optimize=True)
    print("icon:", ICON, flat.size)


def make_splash():
    src = Image.open(os.path.join(RES, "splash_brand.webp")).convert("RGB")
    out = os.path.join(RES, "splash_brand.png")
    src.save(out, "PNG", optimize=True)
    print("splash:", out, src.size)


if __name__ == "__main__":
    make_icon()
    make_splash()
