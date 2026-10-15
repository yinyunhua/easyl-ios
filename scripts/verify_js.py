"""从 Sources/Shell/BridgeScripts.swift 中抽出内嵌的 JS，用 node --check 做真实语法校验。

Swift 原始字符串里的插值 \##(...) 用占位值替换后即为运行时真正注入的脚本。
用法：python scripts/verify_js.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources", "Shell", "BridgeScripts.swift")

BLOCKS = {
    "bridgeJS": "bridge.js",
    "patchJS": "patch.js",
    "handleBackJS": "handle_back.js",
}


def extract_blocks(text):
    """按 `static func NAME(...) -> String {` / `static let NAME = ##\"\"\"` 抓取正文。"""
    found = {}
    # func 形式：return ##""" ... """##
    for name, out in BLOCKS.items():
        if f"static let {name}" in text:
            pattern = re.compile(
                r"static let " + name + r"\s*=\s*##\"\"\"(.*?)\"\"\"##", re.S)
        else:
            pattern = re.compile(
                r"static func " + name + r"\([^)]*\)[^{]*\{(.*?)return\s*##\"\"\"(.*?)\"\"\"##", re.S)
        match = pattern.search(text)
        if not match:
            print(f"[MISS] {name} 未在 BridgeScripts.swift 中找到")
            continue
        body = match.groups()[-1]
        # 插值 -> 占位值（模拟运行时注入的真实形态）
        body = body.replace(r"\##(version)", "2.0.5")
        body = body.replace(r"\##(api)", "https://hgxml.00api-agy5u.com/api")
        body = body.replace(r"\##(backup)", "https://rules.googlexml.com/api")
        body = body.replace(r"\##(sanitize(apiBase))", "https://hgxml.00api-agy5u.com/api")
        body = body.replace(r"\##(sanitize(promoAgentId))", "")
        body = re.sub(r"\\##\([^)]*\)", "PLACEHOLDER", body)
        found[name] = (out, body)
    return found


def main():
    text = open(SRC, encoding="utf-8").read()
    blocks = extract_blocks(text)
    node = shutil.which("node")
    if not node:
        print("未找到 node，无法执行语法校验")
        return 2

    problems = 0
    outdir = os.path.join(ROOT, "_analysis", "jscheck")
    os.makedirs(outdir, exist_ok=True)
    if True:
        tmp = outdir
        for name, (filename, body) in blocks.items():
            path = os.path.join(tmp, filename)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write("(function(){\n" + body + "\n})();\n")
            proc = subprocess.run([node, "--check", path], capture_output=True, text=True)
            status = "OK" if proc.returncode == 0 else "FAIL"
            print(f"[{status}] {name} -> {filename} ({len(body)} chars, {body.count(chr(10)) + 1} lines)")
            if proc.returncode != 0:
                problems += 1
                print(proc.stderr.strip()[:1500])

    print("\n校验完成：%d 段，问题 %d 个" % (len(blocks), problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
