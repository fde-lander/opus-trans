#!/data/data/com.termux/files/usr/bin/bash
# opus-trans — Termux Opus 转码器
# 将 Hi-Res FLAC 批量转码为 Opus 320kbps VBR
# 作者: 超级猪兔兔 🐰
# 日期: 2026-08-02
# Spec: ~/.hermes/docs/superpowers/specs/2026-08-02-opus-trans-design.md

set -euo pipefail

# ── 常量 ──
readonly VERSION="1.1.0"
readonly BITRATE="320k"
readonly SUPPORTED_EXT="flac wav ape wv mp3 m4a aac ogg wma aiff"
# 注意：.opus 也在扫描范围内（可从 opus 转其他格式，但实际场景极少）

# ── 全局变量 ──
TARGET_DIR=""
declare -a FILE_PATHS=()      # 所有音乐文件完整路径
declare -a FILE_GROUPS=()      # 每个文件对应的组字母
declare -a FILE_NUMBERS=()     # 每个文件对应的编号
declare -a GROUP_LETTERS=()    # 所有组字母（有序）
declare -A GROUP_DIRNAMES=()   # 组字母 -> 目录显示名
declare -A GROUP_FILECOUNT=()  # 组字母 -> 文件数
TOTAL_FILES=0

# ── 颜色（Termux 支持 ANSI） ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
MAGENTA='\033[1;35m'   # 目录用 — 紫色粗体
BRIGHTBLUE='\033[1;34m' # 编号用 — 蓝色粗体
NC='\033[0m' # No Color

# ── 辅助函数 ──

print_usage() {
    echo "用法: opus-trans [目录路径]"
    echo ""
    echo "不带参数: 扫描当前目录"
    echo "带参数:   扫描指定目录"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示帮助"
    echo "  -v, --version  显示版本"
    echo ""
    echo "示例:"
    echo "  opus-trans                    # 扫描当前目录"
    echo "  opus-trans /sdcard/Music     # 扫描指定目录"
    echo "  opus-trans ~/storage/music   # 扫描指定目录"
}

print_version() {
    echo -e "${CYAN}🎵 opus-trans${NC} ${BOLD}v${VERSION}${NC} — Hi-Res FLAC → Opus 320k VBR"
}

# ── Phase 1: 前置检查 ──

check_ffmpeg() {
    if ! command -v ffmpeg &>/dev/null; then
        echo -e "${RED}❌ 错误: ffmpeg 未安装${NC}"
        echo ""
        echo "请先安装 ffmpeg:"
        echo "  pkg install ffmpeg"
        exit 1
    fi
}

check_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}❌ 错误: 目录不存在${NC}"
        echo ""
        echo "  ${dir}"
        echo ""
        echo "请检查路径是否正确"
        exit 1
    fi

    if [[ ! -r "$dir" ]]; then
        echo -e "${RED}❌ 错误: 目录无法读取${NC}"
        echo ""
        echo "  ${dir}"
        echo ""
        echo "请检查权限设置"
        exit 1
    fi
}

# ── Phase 2: 递归扫描 + 分组编号 ──

# 将数字转换为字母（1=A, 2=B, ..., 跳过 q, ...）
# 有效字母序列：A B C D E F G H I J K L M N O P R S T U V W X Y Z
number_to_letter() {
    local num=$1
    # 有效组字母 25 个（A-Z 减去 q）
    if [[ $num -lt 1 || $num -gt 25 ]]; then
        echo ""
        return 1
    fi
    # 第 17 个开始（跳过 q 之后）字母表向后偏移 1 位
    local letter_num
    if [[ $num -le 16 ]]; then
        letter_num=$((64 + num))           # 1-16 → A-P
    else
        letter_num=$((64 + num + 1))       # 17-25 → R-Z（跳过 Q）
    fi
    printf "\\$(printf '%03o' "$letter_num")"
}

scan_directory() {
    local root_dir="$1"
    local group_index=1
    local group_letter=""
    local file_number=0
    local current_dir=""
    local prev_dir=""

    # 收集所有子目录（含根目录），按字母排序
    # 根目录排第一，子目录按名称排序
    local all_dirs=()
    all_dirs+=("$root_dir")

    # find 子目录，排序
    while IFS= read -r subdir; do
        all_dirs+=("$subdir")
    done < <(find "$root_dir" -mindepth 1 -type d | sort)

    # 遍历每个目录，查找音乐文件
    for dir in "${all_dirs[@]}"; do
        # 查找该目录（仅当前层级，不递归）中的音乐文件
        local files_in_dir=()
        while IFS= read -r f; do
            [[ -n "$f" ]] && files_in_dir+=("$f")
        done < <(find "$dir" -maxdepth 1 -type f \( -iname "*.flac" -o -iname "*.wav" -o -iname "*.ape" -o -iname "*.wv" -o -iname "*.mp3" -o -iname "*.m4a" -o -iname "*.aac" -o -iname "*.ogg" -o -iname "*.wma" -o -iname "*.aiff" \) | sort)

        # 跳过没有音乐文件的目录
        [[ ${#files_in_dir[@]} -eq 0 ]] && continue

        # 分配组字母
        group_letter=$(number_to_letter "$group_index")
        if [[ -z "$group_letter" ]]; then
            echo -e "${RED}❌ 错误: 子目录超过 25 个，无法分配字母编号${NC}"
            exit 1
        fi

        # 目录显示名
        if [[ "$dir" == "$root_dir" ]]; then
            GROUP_DIRNAMES["$group_letter"]="根目录"
        else
            # 显示相对路径
            local relpath="${dir#$root_dir/}"
            GROUP_DIRNAMES["$group_letter"]="$relpath"
        fi

        GROUP_FILECOUNT["$group_letter"]=${#files_in_dir[@]}
        GROUP_LETTERS+=("$group_letter")

        # 为每个文件分配编号
        file_number=0
        for f in "${files_in_dir[@]}"; do
            ((file_number++)) || true
            FILE_PATHS+=("$f")
            FILE_GROUPS+=("$group_letter")
            FILE_NUMBERS+=("$file_number")
        done

        ((group_index++)) || true
    done

    TOTAL_FILES=${#FILE_PATHS[@]}
}

file_size_human() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$((bytes / 1073741824))GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$((bytes / 1048576))MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$((bytes / 1024))KB"
    else
        echo "${bytes}B"
    fi
}

display_list() {
    if [[ $TOTAL_FILES -eq 0 ]]; then
        echo -e "${YELLOW}📭 目录里没有找到任何音乐文件${NC}"
        echo ""
        echo "支持的格式："
        echo "  flac  wav  ape  wv  mp3  m4a  aac  ogg  wma  aiff"
        exit 0
    fi

    echo -e "${CYAN}🎵 找到 ${TOTAL_FILES} 个音乐文件：${NC}"
    echo ""

    local prev_group=""
    for i in "${!FILE_PATHS[@]}"; do
        local grp="${FILE_GROUPS[$i]}"
        local num="${FILE_NUMBERS[$i]}"
        local fpath="${FILE_PATHS[$i]}"
        local fname
        fname=$(basename "$fpath")

        # 组标题
        if [[ "$grp" != "$prev_group" ]]; then
            echo -e "  ${MAGENTA}${grp} ${GROUP_DIRNAMES[$grp]} (${GROUP_FILECOUNT[$grp]})${NC}"
            prev_group="$grp"
        fi

        # 检查是否已有 .opus
        local base="${fpath%.*}"
        local opus_file="${base}.opus"
        local exists_marker=""
        if [[ -f "$opus_file" ]]; then
            exists_marker=" ${YELLOW}⚠️ 已存在${NC}"
        fi

        # 文件大小
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)

        echo -e "  ${BRIGHTBLUE}${grp}${num}.${NC} ${fname}  ${CYAN}$(file_size_human "$size")${NC}${exists_marker}"
    done

    echo ""
}

# ── Phase 3: 选择解析器 ──

parse_selection() {
    local input="$1"
    local -n _selected_indices=$2  # nameref 返回选中文件的索引数组
    _selected_indices=()

    # 空输入 = all
    if [[ -z "$input" ]]; then
        for i in "${!FILE_PATHS[@]}"; do
            _selected_indices+=("$i")
        done
        return
    fi

    # q / Q = 取消（不用 n，因为 N 可能是组字母）
    local lower_input
    lower_input=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_input" == "q" ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi

    # all / a
    if [[ "$lower_input" == "all" || "$lower_input" == "a" ]]; then
        for i in "${!FILE_PATHS[@]}"; do
            _selected_indices+=("$i")
        done
        return
    fi

    # 解析逗号分隔的选择项
    # 用空格替换逗号，然后遍历
    local IFS=','
    read -ra items <<< "$input"
    unset IFS

    local -A seen_indices=()  # 去重

    for item in "${items[@]}"; do
        # 去除前后空格
        item=$(echo "$item" | xargs)
        # 空 item 跳过
        [[ -z "$item" ]] && continue

        # 小写化用于 q 检测
        local lower_item
        lower_item=$(echo "$item" | tr '[:upper:]' '[:lower:]' | xargs)

        # 单独的 q/Q = 取消
        if [[ "$lower_item" == "q" ]]; then
            echo -e "${YELLOW}已取消${NC}"
            exit 0
        fi

        # q 开头嘅非法组合（q1, q2, qa, etc.）= 静默跳过（用户意图系想取消）
        if [[ "$lower_item" =~ ^q ]]; then
            continue
        fi

        # 转大写
        local upper_item
        upper_item=$(echo "$item" | tr '[:lower:]' '[:upper:]')

        # 范围格式: X1-X3
        if [[ "$upper_item" =~ ^([A-Z])([0-9]+)-([A-Z])([0-9]+)$ ]]; then
            local g1="${BASH_REMATCH[1]}"
            local n1="${BASH_REMATCH[2]}"
            local g2="${BASH_REMATCH[3]}"
            local n2="${BASH_REMATCH[4]}"

            if [[ "$g1" != "$g2" ]]; then
                echo -e "${RED}❌ 范围选择必须在同一组内: ${item}${NC}" >&2
                return 1
            fi

            local start=$n1
            local end=$n2
            if [[ $start -gt $end ]]; then
                local tmp=$start
                start=$end
                end=$tmp
            fi

            for ((n=start; n<=end; n++)); do
                # 查找对应组+编号的文件索引
                local found_in_range=false
                for i in "${!FILE_PATHS[@]}"; do
                    if [[ "${FILE_GROUPS[$i]}" == "$g1" && "${FILE_NUMBERS[$i]}" == "$n" ]]; then
                        if [[ -z "${seen_indices[$i]:-}" ]]; then
                            _selected_indices+=("$i")
                            seen_indices[$i]=1
                        fi
                        found_in_range=true
                        break
                    fi
                done
                # 范围内未找到对应文件时显示警告（不退出，让其他 item 继续解析）
                if ! $found_in_range; then
                    echo -e "${YELLOW}⚠️ 跳过 ${g1}${n}（无此文件）${NC}"
                fi
            done

        # 单个字母+数字: A1
        elif [[ "$upper_item" =~ ^([A-Z])([0-9]+)$ ]]; then
            local grp="${BASH_REMATCH[1]}"
            local num="${BASH_REMATCH[2]}"
            local found=false
            for i in "${!FILE_PATHS[@]}"; do
                if [[ "${FILE_GROUPS[$i]}" == "$grp" && "${FILE_NUMBERS[$i]}" == "$num" ]]; then
                    if [[ -z "${seen_indices[$i]:-}" ]]; then
                        _selected_indices+=("$i")
                        seen_indices[$i]=1
                    fi
                    found=true
                    break
                fi
            done
            # 静默跳过 + 警告，不退出（让其他 item 继续解析）
            if ! $found; then
                echo -e "${YELLOW}⚠️ 跳过 ${item}（无此文件）${NC}"
            fi

        # 单个字母: B (整组)（q 已排除）
        elif [[ "$upper_item" =~ ^([A-PR-Z])$ ]]; then
            local grp="${BASH_REMATCH[1]}"
            local found=false
            for i in "${!FILE_PATHS[@]}"; do
                if [[ "${FILE_GROUPS[$i]}" == "$grp" ]]; then
                    if [[ -z "${seen_indices[$i]:-}" ]]; then
                        _selected_indices+=("$i")
                        seen_indices[$i]=1
                    fi
                    found=true
                fi
            done
            # 静默跳过 + 警告，不退出
            if ! $found; then
                echo -e "${YELLOW}⚠️ 跳过 ${item}（无此组）${NC}"
            fi

        else
            # q 开头嘅已经被前面 continue 跳过
            # 呢度系真正无法识别嘅格式（语法错误）
            echo -e "${RED}❌ 无法识别: ${item}${NC}" >&2
            echo "  格式: A1 / B1-B3 / B / A1,C2 / all" >&2
            return 1
        fi
    done
}

# ── Phase 4: 转码引擎 + 输出命名 ──

generate_output_name() {
    local input_file="$1"
    local base="${input_file%.*}"
    local output="${base}.opus"
    local counter=2

    while [[ -f "$output" ]]; do
        output="${base} (${counter}).opus"
        ((counter++)) || true
    done

    echo "$output"
}

transcode() {
    local input_file="$1"
    local output_file="$2"

    ffmpeg -i "$input_file" \
        -c:a libopus -b:a "$BITRATE" -vbr on \
        -map_metadata 0 \
        -loglevel error \
        "$output_file" 2>&1
}

# ── Phase 5: 交互流程 + 汇总报告 ──

confirm_and_transcode() {
    local -n _indices=$1
    local total=${#_indices[@]}
    local success=0
    local already_exists=0
    local failed=0
    local -a failed_files=()

    echo -e "${CYAN}将转码以下 ${total} 个文件：${NC}"
    for idx in "${_indices[@]}"; do
        local grp="${FILE_GROUPS[$idx]}"
        local num="${FILE_NUMBERS[$idx]}"
        local fpath="${FILE_PATHS[$idx]}"
        local fname
        fname=$(basename "$fpath")

        # 检查是否已有 .opus
        local base="${fpath%.*}"
        local exists_marker=""
        if [[ -f "${base}.opus" ]]; then
            local new_name
            new_name=$(basename "$(generate_output_name "$fpath")")
            exists_marker=" ${YELLOW}→ ${new_name}${NC}"
        fi

        echo -e "  ${BRIGHTBLUE}${grp}${num}.${NC} ${fname}${exists_marker}"
    done
    echo ""
    echo -ne "确认？${BOLD}(y 开始，q 取消，大小写均可)${NC}: "
    read -r confirm

    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi

    echo ""
    local current=0
    for idx in "${_indices[@]}"; do
        ((current++)) || true
        local fpath="${FILE_PATHS[$idx]}"
        local grp="${FILE_GROUPS[$idx]}"
        local num="${FILE_NUMBERS[$idx]}"
        local fname
        fname=$(basename "$fpath")
        local relpath="${fpath#$TARGET_DIR/}"

        # 生成输出文件名
        local output_file
        output_file=$(generate_output_name "$fpath")

        # 检查是否需要新名称
        local base="${fpath%.*}"
        local name_note=""
        if [[ "$output_file" != "${base}.opus" ]]; then
            local new_name
            new_name=$(basename "$output_file")
            name_note=" -> ${CYAN}${new_name}${NC}"
            ((already_exists++)) || true
        fi

        echo -ne "[${current}/${total}] ${relpath}... "

        # 执行转码
        if transcode "$fpath" "$output_file"; then
            # 验证输出
            if [[ -f "$output_file" ]] && [[ $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0) -gt 0 ]]; then
                local out_size
                out_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0)
                echo -e "${GREEN}✅${NC} ${CYAN}$(file_size_human "$out_size")${NC}"
                if [[ -z "$name_note" ]]; then
                    ((success++)) || true
                else
                    echo "       ${CYAN}→ ${new_name}${NC}"
                fi
            else
                echo -e "${RED}❌ 输出验证失败${NC}"
                ((failed++)) || true
                failed_files+=("$fpath")
            fi
        else
            echo -e "${RED}❌ 转码失败${NC}"
            ((failed++)) || true
            failed_files+=("$fpath")
        fi
    done

    echo ""
    echo "━━━ 完成 ━━━"
    echo -e "  📊 总计：${total} 个文件"
    echo -e "  ${GREEN}✅ 成功：${success}${NC}"
    [[ $already_exists -gt 0 ]] && echo -e "  ${YELLOW}🔁 已存在（自动命名）：${already_exists}${NC}"
    [[ $failed -gt 0 ]] && echo -e "  ${RED}❌ 失败：${failed}${NC}"
    echo ""

    if [[ ${#failed_files[@]} -gt 0 ]]; then
        echo "失败文件："
        for f in "${failed_files[@]}"; do
            echo "  - $(basename "$f")"
        done
    fi
}

# ── 主函数 ──

main() {
    print_version
    echo ""

    # 参数解析
    if [[ $# -gt 1 ]]; then
        print_usage
        exit 1
    fi

    if [[ $# -eq 1 ]]; then
        if [[ "$1" == "-h" || "$1" == "--help" ]]; then
            print_usage
            exit 0
        fi
        if [[ "$1" == "-v" || "$1" == "--version" ]]; then
            # print_version 已喺 main() 开头输出
            exit 0
        fi
        TARGET_DIR="$1"
    else
        TARGET_DIR="$(pwd)"
    fi

    # 前置检查
    check_ffmpeg
    check_directory "$TARGET_DIR"

    # 扫描目录
    scan_directory "$TARGET_DIR"

    # 显示文件列表
    display_list

    # 用户选择
    echo -ne "请选择${BOLD}(大小写均可: a1 / b1-b3 / b / a1,c2 / all / q)${NC}: "
    read -r user_selection

    # 解析选择
    declare -a selected_indices=()
    if ! parse_selection "$user_selection" selected_indices; then
        exit 1
    fi

    if [[ ${#selected_indices[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未选择任何文件${NC}"
        exit 0
    fi

    echo ""

    # 确认 + 转码
    confirm_and_transcode selected_indices
}

main "$@"
