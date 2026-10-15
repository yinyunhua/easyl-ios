"""把 Swift 里内嵌的补丁 JS 与 APK dex 中提取的原始字符串做逐行比对。

用法：python scripts/diff_against_apk.py
输出：完全一致的行数 / 差异行（仅空行与缩进差异会被归一化）
"""
import difflib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT_JS = os.path.join(ROOT, "_analysis", "jscheck", "patch.js")
APK_JS = os.path.join(ROOT, "_analysis", "injected_js_full.js")


def load_swift_patch():
    raw = open(SWIFT_JS, encoding="utf-8").read()
    # 去掉 verify_js.py 包裹的 IIFE
    raw = raw.replace("(function(){\n", "", 1)
    if raw.rstrip().endswith("})();"):
        raw = raw.rstrip()[: -len("})();")]
    return [line.strip() for line in raw.splitlines() if line.strip()]


def load_apk_patch():
    text = open(APK_JS, encoding="utf-8", errors="surrogatepass").read()
    # 原始提取包含 handleBack 段 + patch 段：从 patch 的 IIFE 开头切到结尾
    anchor = text.index("window.__HG_PATCH_V1__=true;")
    start = text.rindex("(function(){", 0, anchor)
    patch = text[start:]
    # 去掉注释行差异无关；保留全部非空行
    return [line.strip() for line in patch.splitlines() if line.strip() and not line.strip().startswith("/*")]


def main():
    a = load_swift_patch()
    b = load_apk_patch()
    same = sum(1 for line in a if line in b)
    print(f"Swift 内嵌补丁非空行: {len(a)}")
    print(f"APK dex 原始补丁非空行: {len(b)}")
    print(f"逐行命中: {same}")
    diff = list(difflib.unified_diff(b, a, fromfile="apk", tofile="swift", lineterm="", n=1))
    if not diff:
        print("结果：逐行完全一致")
        return 0
    print("差异（apk=原始, swift=移植）：")
    for line in diff[:80]:
        print(line)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
