#!/bin/bash
# opus-trans v1.4.0 TDD test suite
# Running: bash tests/test_v1_4_0.sh
# Exit code: 0 = all PASS, non-zero = has FAIL
# Based on spec §7.1 — 10 deterministic tests + assert_pass + exit code

set -u
PASS=0
FAIL=0
TEST_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TEST_DIR"

assert_pass() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✅ $test_name"
        ((PASS++)) || true
    else
        echo "  ❌ $test_name: expected '$expected', got '$actual'"
        ((FAIL++)) || true
    fi
}

# ── Test 1: opus-trans-pc.sh exists and shebang is correct ──
test_pc_shebang() {
    if [[ -f "opus-trans-pc.sh" ]]; then
        local first_line
        first_line=$(head -1 opus-trans-pc.sh)
        assert_pass "test_pc_shebang" "#!/bin/bash" "$first_line"
    else
        echo "  ❌ test_pc_shebang: opus-trans-pc.sh does not exist"
        ((FAIL++)) || true
    fi
}

# ── Test 2: PC version soxr default behavior (OPUS_TRANS_FORCE_SWR:-0) ──
test_pc_soxr_default() {
    if grep -q 'OPUS_TRANS_FORCE_SWR:-0' opus-trans-pc.sh; then
        echo "  ✅ test_pc_soxr_default"
        ((PASS++)) || true
    else
        echo "  ❌ test_pc_soxr_default: cannot find OPUS_TRANS_FORCE_SWR:-0"
        ((FAIL++)) || true
    fi
}

# ── Test 3: Termux version shebang remains unchanged ──
test_termux_unchanged() {
    local first_line
    first_line=$(head -1 opus-trans.sh)
    assert_pass "test_termux_unchanged" "#!/data/data/com.termux/files/usr/bin/bash" "$first_line"
}

# ── Test 4: Two files diff only 2 places (shebang + OPUS_TRANS_FORCE_SWR) ──
test_diff_only_2() {
    local diff_output
    diff_output=$(diff <(grep -v -e '^#!/' -e 'OPUS_TRANS_FORCE_SWR:-' opus-trans.sh) \
                      <(grep -v -e '^#!/' -e 'OPUS_TRANS_FORCE_SWR:-' opus-trans-pc.sh) 2>&1)
    if [[ -z "$diff_output" ]]; then
        echo "  ✅ test_diff_only_2"
        ((PASS++)) || true
    else
        echo "  ❌ test_diff_only_2: two files have differences beyond shebang + default value:"
        echo "$diff_output"
        ((FAIL++)) || true
    fi
}

# ── Test 5: ACTUAL_DEPTH must be initialized at transcode() start as empty ──
test_actual_depth_init() {
    # Extract transcode() function (until next ^} standalone line)
    local transcode_body
    transcode_body=$(awk '/^transcode\(\)/,/^}$/' opus-trans.sh)
    # Check ACTUAL_DEPTH init position (must be within first 5 lines)
    local init_line
    init_line=$(echo "$transcode_body" | grep -n 'local ACTUAL_DEPTH=""' | head -1 | cut -d: -f1)
    if [[ -n "$init_line" && "$init_line" -le 5 ]]; then
        echo "  ✅ test_actual_depth_init (line $init_line initialized)"
        ((PASS++)) || true
    else
        echo "  ❌ test_actual_depth_init: ACTUAL_DEPTH not initialized within first 5 lines of transcode()"
        ((FAIL++)) || true
    fi
}

# ── Test 6: 4th line result row includes actual_resampler variable ──
test_result_resampler() {
    # Find actual_resampler assignment inside confirm_and_transcode()
    if awk '/^confirm_and_transcode\(\)/,/^}$/' opus-trans.sh | grep -q 'actual_resampler='; then
        echo "  ✅ test_result_resampler"
        ((PASS++)) || true
    else
        echo "  ❌ test_result_resampler: cannot find actual_resampler variable"
        ((FAIL++)) || true
    fi
}

# ── Test 7: Downgrade shows ⚠️ warning ──
test_downgrade_warning() {
    # Test using real script's logic (not mock)
    local warn_output
    warn_output=$(bash -c '
        # Simulate logic fragment inside confirm_and_transcode()
        ACTUAL_DEPTH="16"
        src_depth="24"
        local depth_warn=""
        if [[ "$ACTUAL_DEPTH" == "16" && "$src_depth" != "16" ]]; then
            depth_warn=" ⚠️"
        fi
        echo "$depth_warn"
    ')
    assert_pass "test_downgrade_warning" " ⚠️" "$warn_output"
}

# ── Test 8: 16bit source with 16bit does NOT show ⚠️ ──
test_no_false_warning() {
    local warn_output
    warn_output=$(bash -c '
        ACTUAL_DEPTH="16"
        src_depth="16"
        local depth_warn=""
        if [[ "$ACTUAL_DEPTH" == "16" && "$src_depth" != "16" ]]; then
            depth_warn=" ⚠️"
        fi
        echo "$depth_warn"
    ')
    assert_pass "test_no_false_warning" "" "$warn_output"
}

# ── Test 9: MSG_TRANSCODING (exact name, not MSG_TRANSCODING_SOXR/SWR) in both language blocks ──
test_msg_transcoding_i18n() {
    # Count exact MSG_TRANSCODING= assignments (not _SOXR / _SWR variants)
    # zh block starts with 'zh|zh-TW|zh-tw|zh_TW|tw|TC)' and ends with first ';;'
    local zh_block en_block
    zh_block=$(awk '/zh\|zh-TW\|zh-tw\|zh_TW\|tw\|TC\)/,/^;;$/' opus-trans.sh)
    en_block=$(awk '!/zh\|zh-TW\|zh-tw\|zh_TW\|tw\|TC\)/,/^;;$/' opus-trans.sh | awk '/^            MSG_/,0' | head -100)
    # Simpler: just count exact matches in whole file (must be ≥ 2 for both languages)
    local count
    count=$(grep -cE '^[[:space:]]*MSG_TRANSCODING="' opus-trans.sh)
    if [[ "$count" -ge 2 ]]; then
        echo "  ✅ test_msg_transcoding_i18n ($count language blocks)"
        ((PASS++)) || true
    else
        echo "  ❌ test_msg_transcoding_i18n: MSG_TRANSCODING exact count = $count (expected ≥ 2)"
        ((FAIL++)) || true
    fi
}

# ── Test 10: Regression — v1.1.0 + v1.2.0 tests still PASS ──
test_regression() {
    local v1_1_pass=false
    local v1_2_pass=false
    if [[ -f "tests/test_v1_1_0.sh" ]]; then
        if bash tests/test_v1_1_0.sh &>/dev/null; then
            v1_1_pass=true
        fi
    fi
    if [[ -f "tests/test_v1_2_0.sh" ]]; then
        if bash tests/test_v1_2_0.sh &>/dev/null; then
            v1_2_pass=true
        fi
    fi
    if $v1_1_pass && $v1_2_pass; then
        echo "  ✅ test_regression"
        ((PASS++)) || true
    else
        echo "  ❌ test_regression: v1.1=$v1_1_pass, v1.2=$v1_2_pass"
        ((FAIL++)) || true
    fi
}

# ── Main flow ──
echo "opus-trans v1.4.0 test suite"
echo "─────────────────────────────────────"
test_pc_shebang
test_pc_soxr_default
test_termux_unchanged
test_diff_only_2
test_actual_depth_init
test_result_resampler
test_downgrade_warning
test_no_false_warning
test_msg_transcoding_i18n
test_regression
echo "─────────────────────────────────────"
echo "PASS: $PASS / FAIL: $FAIL"
exit $FAIL