"""Static checks for the ArkTS sources (no DevEco Studio required).

1. Every relative import resolves to an existing file and the imported symbols
   are actually exported there.
2. Brackets and quotes are balanced (catches the classic copy/paste accident).
3. A few ArkTS-forbidden constructs are flagged (any/unknown/destructuring).

ArkUI declarative syntax cannot be compiled without the OpenHarmony SDK, so
these checks are a safety net, not a substitute for `hvigorw assembleHap`.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ETS_ROOT = ROOT / "entry/src/main/ets"

EXPORT_PATTERNS = [
    re.compile(r"^export\s+(?:abstract\s+)?class\s+(\w+)", re.M),
    re.compile(r"^export\s+enum\s+(\w+)", re.M),
    re.compile(r"^export\s+function\s+(\w+)", re.M),
    re.compile(r"^export\s+const\s+(\w+)", re.M),
    re.compile(r"^export\s+interface\s+(\w+)", re.M),
]
IMPORT_PATTERN = re.compile(r"import\s*\{([^}]*)\}\s*from\s*'([^']+)'", re.S)
FORBIDDEN = [
    (re.compile(r":\s*any\b"), "ArkTS 不支持 any"),
    (re.compile(r":\s*unknown\b"), "ArkTS 不支持 unknown"),
    (re.compile(r"=\s*[A-Za-z_$][\w$]*\.\.\.[A-Za-z_$]"), "疑似展开语法"),
]

problems = []


def exports_of(path):
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8")
    found = set()
    for pattern in EXPORT_PATTERNS:
        found.update(pattern.findall(text))
    return found


def check_balanced(path, text):
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    in_line_comment = False
    in_block_comment = False
    quote = None
    index = 0
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""
        if in_line_comment:
            if char == "\n":
                in_line_comment = False
        elif in_block_comment:
            if char == "*" and nxt == "/":
                in_block_comment = False
                index += 1
        elif quote is not None:
            if char == "\\":
                index += 1
            elif char == quote:
                quote = None
        else:
            if char == "/" and nxt == "/":
                in_line_comment = True
                index += 1
            elif char == "/" and nxt == "*":
                in_block_comment = True
                index += 1
            elif char in "'\"`":
                quote = char
            elif char in "([{":
                stack.append(char)
            elif char in ")]}":
                if not stack or stack[-1] != pairs[char]:
                    problems.append(f"{path}: 括号不匹配，位置 {index}")
                    return
                stack.pop()
        index += 1
    if stack:
        problems.append(f"{path}: 有 {len(stack)} 个未闭合的括号")
    if quote is not None:
        problems.append(f"{path}: 字符串未闭合")


count = 0
for path in sorted(ETS_ROOT.rglob("*.ets")):
    count += 1
    text = path.read_text(encoding="utf-8")
    check_balanced(path, text)

    for match in IMPORT_PATTERN.finditer(text):
        names = [name.strip() for name in match.group(1).split(",") if name.strip()]
        target = match.group(2)
        if not target.startswith("."):
            continue
        resolved = (path.parent / target).resolve()
        resolved = resolved.with_suffix(".ets") if resolved.suffix != ".ets" else resolved
        if not resolved.exists():
            problems.append(f"{path}: 找不到模块 {target}")
            continue
        available = exports_of(resolved)
        for name in names:
            bare = name.split(" as ")[0].strip()
            if bare not in available:
                problems.append(f"{path}: 模块 {target} 未导出 {bare}")

    for pattern, message in FORBIDDEN:
        for match in pattern.finditer(text):
            line = text[: match.start()].count("\n") + 1
            problems.append(f"{path}:{line}: {message}")

print(f"checked {count} ArkTS file(s)")
if problems:
    for problem in problems:
        print(f"  ERROR {problem}")
    sys.exit(1)
print("no problems found")
