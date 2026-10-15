# 自研 Swift 符号一致性检查：对 `model.<x>(` / `self.<x>(` / `self?.<x>(` / `webView?.<x>(` 形式的方法调用，
# 要求本项目源码里存在对应 `func <x>(` 定义（系统 API 调用一般不走这些前缀，误报率低）。
#
# 用法：python scripts/lint_swift_symbols.py
# 起因：一次脚本补丁因锚点文案不匹配被静默跳过，只补了调用没补定义 → CI 才会报 “cannot find in scope”。
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources")

# 允许的“非自研”成员名（UIKit/Foundation/SwiftUI 常见属性方法，带前缀调用但无需自研定义）
ALLOW = {
    "init", "shared", "frame", "load", "reload", "sheet", "alert", "position", "opacity",
    "publisher", "onReceive", "task", "onAppear", "onChange",
}


def string_block_lines(text):
    """返回落在 Swift 多行字符串字面量内部的行号集合（这些行里是 JS/HTML，不是 Swift 代码）。"""
    inside = set()
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        opened = None
        for delim in ('##"""', '#"""', '"""'):
            if delim in line and not line[line.index(delim) + len(delim):].strip().startswith("#"):
                opened = delim
                break
        if not opened:
            i += 1
            continue
        closing = ('"""##' if opened == '##"""' else ('"""#' if opened == '#"""' else '"""'))
        j = i + 1
        while j < len(lines) and lines[j].strip() != closing:
            inside.add(j + 1)
            j += 1
        i = j + 1
    return inside


def main():
    files = sorted(glob.glob(os.path.join(SRC, "**", "*.swift"), recursive=True))
    sources = {p: open(p, encoding="utf-8").read() for p in files}
    skip = {p: string_block_lines(text) for p, text in sources.items()}
    defs = set()
    for text in sources.values():
        defs.update(re.findall(r"func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text))
        defs.update(re.findall(r"var\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:=]", text))
        defs.update(re.findall(r"let\s+([A-Za-z_][A-Za-z0-9_]*)\s*[:=]", text))

    # 只检查「接收者必然是自研类型」的调用：model / self
    call_re = re.compile(r"(?:\bmodel|\bself)\s*\.\s*([a-zA-Z_][A-Za-z0-9_]*)\s*\(")
    problems = 0
    for path, text in sources.items():
        for idx, line in enumerate(text.split("\n"), 1):
            if idx in skip[path]:
                continue
            for match in call_re.finditer(line):
                name = match.group(1)
                if name in defs or name in ALLOW:
                    continue
                print(f"{os.path.relpath(path, ROOT)}:{idx}: 调用了未定义的 {name}(  ->  {line.strip()[:100]}")
                problems += 1
    # 第二遍：本项目命名风格的「裸调用」（无接收者）也必须有定义。
    # 这一条专门覆盖真实踩过的坑：脚本补丁只加了 `schedulePlayerLayout()` 调用、没加定义 →
    # Xcode 才报 “cannot find 'schedulePlayerLayout' in scope”。
    own_prefix = re.compile(
        r"^(?:schedule|apply|layout|update|enter|exit|verify|show|load|push|handle|inject|dismiss|"
        r"bootstrap|notify|request|perform|capture|save|toggle|install|openUrl|probe|pick|set)[A-Z]"
    )
    bare_re = re.compile(r"(?<![\w.$])([a-z][A-Za-z0-9_]*)\s*\(")
    for path, text in sources.items():
        for idx, line in enumerate(text.split("\n"), 1):
            if idx in skip[path]:
                continue
            stripped = line.strip()
            if stripped.startswith("func ") or stripped.startswith("//") or stripped.startswith("///"):
                continue
            code = line.split("//", 1)[0]          # 去掉行尾注释（注释里会写 Android 侧 API 名）
            for match in bare_re.finditer(code):
                name = match.group(1)
                if name in defs or name in ALLOW or not own_prefix.match(name):
                    continue
                print(f"{os.path.relpath(path, ROOT)}:{idx}: 裸调用了未定义的 {name}(  ->  {stripped[:100]}")
                problems += 1

    print(f"\n符号一致性检查完成：问题 {problems} 处")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
