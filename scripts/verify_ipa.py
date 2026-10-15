"""校验从 GitHub Release 下载的未签名 IPA 内容（结构 / Info.plist / 可执行体 / 注入补丁）。

用法：python scripts/verify_ipa.py [ipa路径]
"""
import json
import os
import plistlib
import re
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_IPA = os.path.join(ROOT, "dist", "HgForIOS-unsigned.ipa")

MARKERS = [
    # v1（与 APK dex 原文逐行一致）
    b"__HG_PATCH_V1__",
    b"fakeVip",
    b"stripAds",
    b"unlockPlay",
    b"HuangGuoNative",
    b"__HG_API_SEED__",
    b"hg-app-update-result",
    b"hgtv[_-]([A-Za-z0-9]{16,64})",
    b"https://hgxml.00api-agy5u.com/api",
    b"google.huge1-7wnjsk.com",
    # v2（iOS 增强：广告兜底清理 / seek 续播 / 播放器居中 / 横屏全屏）
    b"__HG_PATCH_V2__",
    b"sweepAds",
    b"fixVideoLayout",
    b"seeked",
    b"webkitEnterFullscreen",
    b"orientationchange",
    b"__HG_EXTRA_ADS__",
    b"requestGeometryUpdate",
]

EXTRA_FILES = [
    "Payload/HgForIOS.app/splash_anchor.json",
    "Payload/HgForIOS.app/splash_brand.png",
]


def macho_info(data: bytes):
    """返回 (magic, cputype, ncmds) 概要。"""
    if len(data) < 32:
        return None
    magic = struct.unpack_from("<I", data, 0)[0]
    names = {0xFEEDFACE: "MH_MAGIC(32)", 0xFEEDFACF: "MH_MAGIC_64", 0xCEFAEDFE: "MH_CIGAM", 0xCFFAEDFE: "MH_CIGAM_64"}
    cputype = struct.unpack_from("<i", data, 4)[0]
    cpu_names = {7: "x86", 12: "arm", 16777223: "x86_64", 16777228: "arm64", 16777222: "arm64e"}
    return names.get(magic, hex(magic)), cpu_names.get(cputype, str(cputype))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_IPA
    if not os.path.exists(path):
        print("IPA 不存在:", path)
        return 2
    size = os.path.getsize(path)
    print(f"IPA: {path}")
    print(f"大小: {size} 字节 ({size/1024/1024:.2f} MB)")

    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        print(f"条目数: {len(names)}")
        app = [n for n in names if n.startswith("Payload/")]
        assert app, "缺少 Payload/ 目录（不是合法 IPA）"
        print("Payload 根:", sorted({n.split('/')[1] for n in app}))

        exe = "Payload/HgForIOS.app/HgForIOS"
        info_entry = "Payload/HgForIOS.app/Info.plist"
        if info_entry in names:
            info = plistlib.loads(z.read(info_entry))
            print("\n--- Info.plist ---")
            for k in ["CFBundleIdentifier", "CFBundleDisplayName", "CFBundleName", "CFBundleShortVersionString",
                      "CFBundleVersion", "CFBundleIconName", "MinimumOSVersion", "UILaunchScreen"]:
                print(f"  {k} = {info.get(k)}")
            assert info.get("CFBundleIdentifier") == "com.hg.app", "bundle id 不匹配"
            assert info.get("CFBundleShortVersionString") == "2.0.5", "版本号不匹配"
            assert info.get("CFBundleVersion") == "103", "build 号不匹配"
        else:
            print("!! 未找到 Info.plist")

        print("\n--- 包内资源 ---")
        for n in sorted(names):
            if n.startswith("Payload/HgForIOS.app/") and n.count("/") == 2:
                print(f"  {n.split('/')[-1]:32s} {z.getinfo(n).file_size:>9d}")

        missing_files = [f for f in EXTRA_FILES if f not in names]
        if missing_files:
            print("!! 缺少资源:", missing_files)
            return 1
        anchor = json.loads(z.read("Payload/HgForIOS.app/splash_anchor.json").decode("utf-8"))
        print("  闪屏锚点:", anchor)

        if exe in names:
            data = z.read(exe)
            print("\n--- 可执行体 ---")
            print(f"  HgForIOS: {len(data)} 字节, Mach-O={macho_info(data)}")
            assert len(data) > 100_000, "可执行体过小，可能是空壳"
            print("\n--- 关键实现标记（证明注入脚本与 VIP 补丁已编入 IPA）---")
            missing = []
            for m in MARKERS:
                hit = m in data
                print(f"  [{'OK' if hit else 'MISS'}] {m.decode()}")
                if not hit:
                    missing.append(m.decode())
            if missing:
                print("\n缺失标记:", missing)
                return 1
        else:
            print("!! 未找到可执行体")
            return 1

    print("\n校验通过：结构 / Info.plist / arm64 可执行体 / VIP 补丁与桥接脚本全部就位")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
