#!/usr/bin/env bash
# test_v1_1_0.sh — TDD 验证脚本 for opus-trans v1.1.0 列表美化
# 用法: bash tests/test_v1_1_0.sh
# 返回: 0=全部 PASS, 1=有 FAIL

set -euo pipefail

SCRIPT_PATH="/home/hermes/workspace/opus-trans/opus-trans.sh"
PASS=0
FAIL=0

ok()   { echo "  ✅ $1"; ((PASS++)) || true; }
fail() { echo "  ❌ $1"; ((FAIL++)) || true; }

echo "=== opus-trans v1.1.0 TDD 验证 ==="
echo ""

# ── 测试组 1：颜色常量存在 ──
echo "--- 测试组 1：颜色常量 ---"

# T1.1: MAGENTA 常量存在
if grep -q "MAGENTA=" "$SCRIPT_PATH"; then
    ok "T1.1 MAGENTA 常量存在"
else
    fail "T1.1 MAGENTA 常量不存在"
fi

# T1.2: BOLDGREEN 常量存在
if grep -q "BOLDGREEN=" "$SCRIPT_PATH"; then
    ok "T1.2 BOLDGREEN 常量存在"
else
    fail "T1.2 BOLDGREEN 常量不存在"
fi

# T1.3: MAGENTA 值正确 (1;35m)
if grep -q "MAGENTA=.\\\\033\[1;35m" "$SCRIPT_PATH"; then
    ok "T1.3 MAGENTA 值为 \\033[1;35m"
else
    fail "T1.3 MAGENTA 值不正确"
fi

# T1.4: BOLDGREEN 值正确 (1;32m)
if grep -q "BOLDGREEN=.\\\\033\[1;32m" "$SCRIPT_PATH"; then
    ok "T1.4 BOLDGREEN 值为 \\033[1;32m"
else
    fail "T1.4 BOLDGREEN 值不正确"
fi

# ── 测试组 2：display_list() 目录行使用 MAGENTA ──
echo "--- 测试组 2：display_list 目录行 ---"

# T2.1: display_list 中目录行使用 MAGENTA（而非 BOLD）
# 搜索 display_list 函数内的目录行
if sed -n '/^display_list/,/^}/p' "$SCRIPT_PATH" | grep -q "MAGENTA.*GROUP_DIRNAMES"; then
    ok "T2.1 display_list 目录行使用 MAGENTA"
else
    fail "T2.1 display_list 目录行未使用 MAGENTA"
fi

# T2.2: 目录行有 2 空格缩进
if sed -n '/^display_list/,/^}/p' "$SCRIPT_PATH" | grep -E '^\s*echo.*MAGENTA.*GROUP_DIRNAMES' | grep -q '^  '; then
    ok "T2.2 目录行有 2 空格缩进"
else
    fail "T2.2 目录行缩进不正确"
fi

# T2.3: 目录行不再使用 BOLD（不应有 BOLD.*GROUP_DIRNAMES）
if ! sed -n '/^display_list/,/^}/p' "$SCRIPT_PATH" | grep -q 'BOLD.*GROUP_DIRNAMES'; then
    ok "T2.3 目录行不再使用 BOLD"
else
    fail "T2.3 目录行仍使用 BOLD（应改为 MAGENTA）"
fi

# ── 测试组 3：display_list() 文件行编号使用 BRIGHTBLUE ──
echo "--- 测试组 3：display_list 文件行编号 ---"

# T3.1: 文件行编号使用 BOLDGREEN
if sed -n '/^display_list/,/^}/p' "$SCRIPT_PATH" | grep -q 'BOLDGREEN.*\${grp}\${num}'; then
    ok "T3.1 文件行编号使用 BOLDGREEN"
else
    fail "T3.1 文件行编号未使用 BOLDGREEN"
fi

# ── 测试组 4：confirm_and_transcode() 确认列表编号使用 BOLDGREEN ──
echo "--- 测试组 4：confirm_and_transcode 确认列表 ---"

# T4.1: 确认列表编号使用 BOLDGREEN
if sed -n '/^confirm_and_transcode/,/^}/p' "$SCRIPT_PATH" | grep -q 'BOLDGREEN.*\${grp}\${num}'; then
    ok "T4.1 确认列表编号使用 BOLDGREEN"
else
    fail "T4.1 确认列表编号未使用 BOLDGREEN"
fi

# ── 测试组 5：版本号 ──
echo "--- 测试组 5：版本号 ---"

# T5.1: VERSION = 1.1.0
if grep -q 'readonly VERSION="1.1.0"' "$SCRIPT_PATH"; then
    ok "T5.1 VERSION = 1.1.0"
else
    fail "T5.1 VERSION 不是 1.1.0"
fi

# ── 测试组 6：功能逻辑不变（回归保护）──
echo "--- 测试组 6：回归保护 ---"

# T6.1: 转码命令不变（跨行，分别检查关键参数）
if grep -q '\-c:a libopus' "$SCRIPT_PATH" && grep -q '\-b:a.*BITRATE' "$SCRIPT_PATH" && grep -q '\-vbr on' "$SCRIPT_PATH" && grep -q '\-map_metadata 0' "$SCRIPT_PATH"; then
    ok "T6.1 转码命令保持不变"
else
    fail "T6.1 转码命令被修改"
fi

# T6.2: parse_selection 函数仍存在
if grep -q '^parse_selection()' "$SCRIPT_PATH"; then
    ok "T6.2 parse_selection() 存在"
else
    fail "T6.2 parse_selection() 缺失"
fi

# T6.3: set -euo pipefail 仍存在
if grep -q 'set -euo pipefail' "$SCRIPT_PATH"; then
    ok "T6.3 set -euo pipefail 存在"
else
    fail "T6.3 set -euo pipefail 缺失"
fi

# T6.4: 没有 ANSI 清屏（v2.0.0 铁律）
if ! grep -q '\\033\[2J' "$SCRIPT_PATH"; then
    ok "T6.4 无 ANSI 清屏（正确）"
else
    fail "T6.4 检测到 ANSI 清屏（违反铁律）"
fi

# T6.5: 没有 raw mode（v2.0.0 铁律）
if ! grep -q 'stty raw' "$SCRIPT_PATH"; then
    ok "T6.5 无 raw mode（正确）"
else
    fail "T6.5 检测到 raw mode（违反铁律）"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "总计: $((PASS + FAIL)) | PASS: $PASS | FAIL: $FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
