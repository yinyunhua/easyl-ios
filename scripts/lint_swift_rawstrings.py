# 本地校验 Swift 多行字符串字面量的缩进规则（Swift 要求：正文每行缩进 >= 收尾定界符缩进）。
#
# 用法：python scripts/lint_swift_rawstrings.py
# 适用于 Sources/**/*.swift，覆盖普通三引号与带 # 前缀的原始字符串两种形态。
# 这条检查是补上一个真实事故：用脚本把 JS 拼进 Swift 时给收尾定界符多加了缩进，
# 正文缩进不足 → Xcode 报 "insufficient indentation of line in multi-line string literal"。
import glob
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Sources")


def opening_delim(line):
    """返回该行出现的多行字符串开始定界符（含 # 前缀），没有则 None。"""
    for delim in ('##"""', '#"""', '"""'):
        idx = line.find(delim)
        if idx >= 0:
            # 排除收尾定界符（形如 """##）
            tail = line[idx + len(delim):]
            if tail.strip().startswith("#"):
                continue
            return delim
    return None


def check_file(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    problems = []
    i = 0
    while i < len(lines):
        delim = opening_delim(lines[i])
        if delim is None:
            i += 1
            continue
        closing = ('"""##' if delim == '##"""' else ('"""#' if delim == '#"""' else '"""'))
        start = i
        j = i + 1
        while j < len(lines) and lines[j].strip() != closing:
            j += 1
        if j >= len(lines):
            problems.append((start + 1, "未找到收尾定界符 " + closing))
            i += 1
            continue
        closing_indent = len(lines[j]) - len(lines[j].lstrip())
        for k in range(start + 1, j):
            raw = lines[k]
            if not raw.strip():
                continue
            indent = len(raw) - len(raw.lstrip())
            if indent < closing_indent:
                problems.append((k + 1, f"缩进 {indent} < 收尾定界符缩进 {closing_indent}: {raw.strip()[:60]}"))
        i = j + 1
    return problems


def main():
    total = 0
    for path in sorted(glob.glob(os.path.join(SRC, "**", "*.swift"), recursive=True)):
        problems = check_file(path)
        for line_no, message in problems:
            total += 1
            print(f"{os.path.relpath(path, ROOT)}:{line_no}: {message}")
    print(f"\n多行字符串缩进检查完成：问题 {total} 处")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
