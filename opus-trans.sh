#!/data/data/com.termux/files/usr/bin/bash
# opus-trans — Termux Opus 转码器
# 将 Hi-Res FLAC 批量转码为 Opus 320kbps VBR
# 作者: 超级猪兔兔 🐰
# 日期: 2026-08-02
# Spec: ~/.hermes/docs/superpowers/specs/2026-08-02-opus-trans-design.md

set -euo pipefail

# ── 常量 ──
readonly VERSION="2.0.0"
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

# ── Phase 2b: 分页浏览系统 ──

# 全局：显示行数据
declare -a DISPLAY_LINES=()
DISPLAY_LINE_COUNT=0

# 获取终端行数，fallback 15
get_terminal_lines() {
    local lines
    lines=$(tput lines 2>/dev/null) || lines=""
    if [[ -z "$lines" || "$lines" -lt 10 ]]; then
        echo 15
    else
        echo "$lines"
    fi
}

# 构建 display lines（替代旧 display_list 的 echo 逻辑）
# DISPLAY_LINES 每行包含：类型|内容
# 类型：header=标题, group=组标题, file=文件行
build_display_lines() {
    DISPLAY_LINES=()
    DISPLAY_LINE_COUNT=0

    if [[ $TOTAL_FILES -eq 0 ]]; then
        DISPLAY_LINES+=("empty|没有音乐文件")
        DISPLAY_LINE_COUNT=1
        return
    fi

    DISPLAY_LINES+=("header|🎵 找到 ${TOTAL_FILES} 个音乐文件：")
    DISPLAY_LINE_COUNT=1
    DISPLAY_LINES+=("blank|")
    DISPLAY_LINE_COUNT=2

    local prev_group=""
    for i in "${!FILE_PATHS[@]}"; do
        local grp="${FILE_GROUPS[$i]}"
        local num="${FILE_NUMBERS[$i]}"
        local fpath="${FILE_PATHS[$i]}"
        local fname
        fname=$(basename "$fpath")

        # 组标题
        if [[ "$grp" != "$prev_group" ]]; then
            DISPLAY_LINES+=("group|${grp}|${GROUP_DIRNAMES[$grp]}|${GROUP_FILECOUNT[$grp]}|${grp}")
            DISPLAY_LINE_COUNT=$((DISPLAY_LINE_COUNT + 1))
            prev_group="$grp"
        fi

        # 检查是否已有 .opus
        local base="${fpath%.*}"
        local opus_file="${base}.opus"
        local exists_marker=""
        if [[ -f "$opus_file" ]]; then
            exists_marker=" ⚠️"
        fi

        # 文件大小
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)

        DISPLAY_LINES+=("file|${grp}${num}|${fname}|$(file_size_human "$size")${exists_marker}")
        DISPLAY_LINE_COUNT=$((DISPLAY_LINE_COUNT + 1))
    done
}

# 渲染指定范围的行
# 参数：$1=start_index, $2=end_index (inclusive), $3=total_pages, $4=current_page, $5=input_buffer
render_page() {
    local start=$1
    local end=$2
    local total_pages=$3
    local current_page=$4
    local input_buf=$5

    local term_lines
    term_lines=$(get_terminal_lines)

    # 清屏
    printf '\033[2J\033[H'

    # 渲染行
    local i=$start
    local prev_group=""
    while [[ $i -le $end && $i -lt $DISPLAY_LINE_COUNT ]]; do
        local line="${DISPLAY_LINES[$i]}"
        IFS='|' read -r type rest <<< "$line"
        case "$type" in
            header)
                echo -e "${CYAN}${rest}${NC}"
                ;;
            blank)
                echo ""
                ;;
            group)
                # 格式: group|grp_letter|dirname|count|extra
                IFS='|' read -r _ grp_letter dirname count _rest <<< "$line"
                # 检查是否需要（续）标记
                local show_cont=false
                if [[ $i -gt 0 && $i -ne $start ]]; then
                    local prev_line="${DISPLAY_LINES[$((i-1))]}"
                    local prev_type
                    prev_type="${prev_line%%|*}"
                    if [[ "$prev_type" == "file" ]]; then
                        local prev_code
                        prev_code=$(echo "$prev_line" | cut -d'|' -f2)
                        local prev_grp="${prev_code//[0-9]/}"
                        if [[ "$prev_grp" == "$grp_letter" ]]; then
                            show_cont=true
                        fi
                    fi
                fi
                if $show_cont; then
                    echo -e "${BOLD}${grp_letter} ${dirname} (${count})（续）${NC}"
                else
                    echo -e "${BOLD}${grp_letter} ${dirname} (${count})${NC}"
                fi
                ;;
            file)
                IFS='|' read -r _ code fname size_marker <<< "$line"
                # 去除 exists marker 单独处理颜色
                local exists=""
                if [[ "$size_marker" == *"⚠️"* ]]; then
                    exists=" ${YELLOW}⚠️ 已存在${NC}"
                    size_marker="${size_marker%% ⚠️}"
                fi
                echo -e "  ${code}. ${fname}  ${CYAN}${size_marker}${NC}${exists}"
                ;;
        esac
        i=$((i + 1))
    done

    # 状态栏
    echo ""
    if [[ $total_pages -gt 1 ]]; then
        echo -e "${BOLD}━━ 第 ${current_page}/${total_pages} 页 ━━${NC} PgUp/PgDn/↑/↓ 翻页 | ESC=取消"
    else
        echo -e "${BOLD}━━ 全部 ${TOTAL_FILES} 个文件 ━━${NC} ESC=取消"
    fi

    # 输入栏
    echo ""
    echo -ne "选择: ${input_buf}"
}

# 计算总页数
calc_total_pages() {
    local page_lines=$1
    # 减去固定行：状态栏(1) + 空行(1) + 输入栏(1) = 3行
    # header(1) + blank(1) = 2行（只在内容里）
    local content_lines=$((page_lines - 3))
    if [[ $content_lines -lt 1 ]]; then
        content_lines=1
    fi
    local total_content=$((DISPLAY_LINE_COUNT - 2))  # 减去 header + blank
    if [[ $total_content -le 0 ]]; then
        total_content=1
    fi
    echo $(( (total_content + content_lines - 1) / content_lines ))
}

# 主分页选择循环
paginate_and_select() {
    local -n _sel_indices=$1
    _sel_indices=()

    # 空目录特殊处理
    if [[ $TOTAL_FILES -eq 0 ]]; then
        echo -e "${YELLOW}📭 目录里没有找到任何音乐文件${NC}"
        echo ""
        echo "支持的格式："
        echo "  flac  wav  ape  wv  mp3  m4a  aac  ogg  wma  aiff"
        exit 0
    fi

    # 构建 display lines
    build_display_lines

    local term_lines
    term_lines=$(get_terminal_lines)

    # 每页可用内容行数 = 终端行数 - 3（状态栏+空行+输入栏）
    local page_lines=$((term_lines - 3))

    # 总内容行（减去 header + blank）
    local total_content=$((DISPLAY_LINE_COUNT - 2))

    # 总页数
    local total_pages
    if [[ $total_content -le $page_lines ]]; then
        total_pages=1
    else
        total_pages=$(( (total_content + page_lines - 1) / page_lines ))
    fi

    local current_page=1
    local input_buf=""

    # 进入 raw mode
    stty raw -echo 2>/dev/null || true
    trap 'stty sane 2>/dev/null' EXIT

    while true; do
        # 计算当前页的起始和结束 index
        local start_idx
        if [[ $current_page -eq 1 ]]; then
            start_idx=0
        else
            # 第2页开始跳过 header+blank
            start_idx=$((2 + (current_page - 1) * page_lines))
        fi
        local end_idx=$((start_idx + page_lines - 1))
        [[ $end_idx -ge $DISPLAY_LINE_COUNT ]] && end_idx=$((DISPLAY_LINE_COUNT - 1))

        # 渲染当前页
        render_page "$start_idx" "$end_idx" "$total_pages" "$current_page" "$input_buf"

        # 读取按键
        local byte1
        byte1=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
        byte1="${byte1:-0}"

        # 处理按键
        if [[ $byte1 -eq 27 ]]; then
            # ESC sequence - 尝试读取后续 byte
            local byte2
            byte2=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
            byte2="${byte2:-0}"

            if [[ $byte2 -eq 0 ]]; then
                # 单个 ESC（超时无后续）-> 取消
                stty sane 2>/dev/null
                echo ""
                echo -e "${YELLOW}已取消${NC}"
                exit 0
            elif [[ $byte2 -eq 91 ]]; then
                # [ 开头的 escape sequence
                local byte3
                byte3=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' ')
                byte3="${byte3:-0}"

                if [[ $byte3 -eq 53 ]]; then
                    # PgUp: ESC[5~ - 还需要读 ~
                    dd bs=1 count=1 2>/dev/null > /dev/null
                    if [[ $current_page -gt 1 ]]; then
                        current_page=$((current_page - 1))
                    fi
                elif [[ $byte3 -eq 54 ]]; then
                    # PgDn: ESC[6~ - 还需要读 ~
                    dd bs=1 count=1 2>/dev/null > /dev/null
                    if [[ $current_page -lt $total_pages ]]; then
                        current_page=$((current_page + 1))
                    fi
                elif [[ $byte3 -eq 65 ]]; then
                    # ↑ - 上翻半页
                    if [[ $current_page -gt 1 ]]; then
                        current_page=$((current_page - 1))
                    fi
                elif [[ $byte3 -eq 66 ]]; then
                    # ↓ - 下翻半页
                    if [[ $current_page -lt $total_pages ]]; then
                        current_page=$((current_page + 1))
                    fi
                fi
                # 其他 ESC sequence 忽略
            else
                # ESC + 非 [ 字符，忽略
                :
            fi

        elif [[ $byte1 -eq 13 || $byte1 -eq 10 ]]; then
            # Enter - 提交
            stty sane 2>/dev/null
            echo ""
            break

        elif [[ $byte1 -eq 127 || $byte1 -eq 8 ]]; then
            # Backspace
            if [[ ${#input_buf} -gt 0 ]]; then
                input_buf="${input_buf%?}"
            fi

        elif [[ $byte1 -ge 32 && $byte1 -le 126 ]]; then
            # 可打印 ASCII
            local char
            char=$(printf "\\$(printf '%03o' "$byte1")")

            # q 键特殊处理
            if [[ "$char" == "q" || "$char" == "Q" ]]; then
                if [[ -z "$input_buf" ]]; then
                    # 空缓冲区 -> 取消
                    stty sane 2>/dev/null
                    echo ""
                    echo -e "${YELLOW}已取消${NC}"
                    exit 0
                fi
            fi

            input_buf="${input_buf}${char}"

        elif [[ $byte1 -eq 3 ]]; then
            # Ctrl+C
            stty sane 2>/dev/null
            echo ""
            exit 1
        fi
    done

    # 恢复终端
    stty sane 2>/dev/null

    # 解析选择
    if [[ -z "$input_buf" ]]; then
        # 空输入 = all
        for i in "${!FILE_PATHS[@]}"; do
            _sel_indices+=("$i")
        done
        return
    fi

    if ! parse_selection "$input_buf" _sel_indices; then
        exit 1
    fi
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

# ── Phase 4b: 实时进度转码 ──

# 获取音频时长（秒），失败返回空
get_duration() {
    local fpath="$1"
    local dur
    dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$fpath" 2>/dev/null) || dur=""
    if [[ -z "$dur" || "$dur" == "N/A" ]]; then
        echo ""
    else
        echo "$dur"
    fi
}

# 秒数转 mm:ss
format_time() {
    local total_sec=$1
    local min=$((total_sec / 60))
    local sec=$((total_sec % 60))
    printf "%02d:%02d" "$min" "$sec"
}

# 绘制进度条（20格）
draw_progress_bar() {
    local percent=$1
    local filled=$((percent * 20 / 100))
    [[ $filled -gt 20 ]] && filled=20
    [[ $filled -lt 0 ]] && filled=0
    local empty=$((20 - filled))
    local bar=""
    local i
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# 带进度条的转码函数
# 参数：$1=input, $2=output, $3=duration_seconds, $4=current/total
# 返回：0=成功, 1=失败
transcode_with_progress() {
    local input_file="$1"
    local output_file="$2"
    local duration="$3"
    local current="$4"
    local total="$5"
    local relpath="${input_file#$TARGET_DIR/}"

    local has_progress=false
    if [[ -n "$duration" ]]; then
        has_progress=true
    fi

    # 创建临时文件接收 progress 输出
    local progress_file
    progress_file=$(mktemp)

    # 后台运行 ffmpeg
    ffmpeg -i "$input_file" \
        -c:a libopus -b:a "$BITRATE" -vbr on \
        -map_metadata 0 \
        -progress "$progress_file" \
        -loglevel error \
        "$output_file" 2>/dev/null &
    local ffmpeg_pid=$!

    # spinner 字符
    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_idx=0

    # 监控进度
    while kill -0 "$ffmpeg_pid" 2>/dev/null; do
        if $has_progress; then
            # 读取 progress 文件最后的 out_time_us
            local out_time_us=""
            if [[ -f "$progress_file" ]]; then
                out_time_us=$(grep "out_time_us=" "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)
            fi
            local speed=""
            if [[ -f "$progress_file" ]]; then
                speed=$(grep "speed=" "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2 | tr -d ' ')
            fi
            local total_size=""
            if [[ -f "$progress_file" ]]; then
                total_size=$(grep "total_size=" "$progress_file" 2>/dev/null | tail -1 | cut -d'=' -f2)
            fi

            if [[ -n "$out_time_us" && "$out_time_us" != "0" ]]; then
                local processed_sec=$((out_time_us / 1000000))
                local percent=$((processed_sec * 100 / ${duration%.*}))
                [[ $percent -gt 100 ]] && percent=100
                [[ $percent -lt 0 ]] && percent=0
                local bar
                bar=$(draw_progress_bar "$percent")
                local time_str
                time_str="$(format_time "$processed_sec")/$(format_time "${duration%.*}")"

                # bitrate 计算
                local bitrate_str=""
                if [[ -n "$total_size" && "$total_size" != "N/A" && "$processed_sec" -gt 0 ]]; then
                    local kbps=$((total_size * 8 / 1000 / processed_sec))
                    bitrate_str=" | ${kbps}kb/s"
                fi

                printf "\r[${current}/${total}] %s | %s %d%% | %s | %s%s    " \
                    "$relpath" "$bar" "$percent" "$time_str" "${speed:-?}" "$bitrate_str"
            else
                printf "\r[${current}/${total}] %s %s 转码中...    " \
                    "$relpath" "${spinner_chars[$spinner_idx]}"
            fi
        else
            # spinner 模式
            printf "\r[${current}/${total}] %s %s 转码中...    " \
                "$relpath" "${spinner_chars[$spinner_idx]}"
        fi

        spinner_idx=$(( (spinner_idx + 1) % 10 ))
        sleep 0.2
    done

    # 等待 ffmpeg 结束
    wait "$ffmpeg_pid"
    local exit_code=$?

    rm -f "$progress_file"

    # 验证输出
    if [[ $exit_code -eq 0 && -f "$output_file" ]]; then
        local out_size
        out_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0)
        if [[ $out_size -gt 0 ]]; then
            printf "\r[${current}/${total}] ✅ %s -> %s                              \n" \
                "$relpath" "$(file_size_human "$out_size")"
            return 0
        fi
    fi

    printf "\r[${current}/${total}] ❌ %s 转码失败                              \n" "$relpath"
    return 1
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
            exists_marker=" ${YELLOW}-> ${new_name}${NC}"
        fi

        echo "  ${grp}${num}. ${fname}${exists_marker}"
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
    local start_time
    start_time=$(date +%s)

    for idx in "${_indices[@]}"; do
        ((current++)) || true
        local fpath="${FILE_PATHS[$idx]}"
        local grp="${FILE_GROUPS[$idx]}"
        local num="${FILE_NUMBERS[$idx]}"
        local fname
        fname=$(basename "$fpath")

        # 生成输出文件名
        local output_file
        output_file=$(generate_output_name "$fpath")

        # 检查是否需要新名称
        local base="${fpath%.*}"
        if [[ "$output_file" != "${base}.opus" ]]; then
            ((already_exists++)) || true
        fi

        # 获取时长
        local duration
        duration=$(get_duration "$fpath")

        # 执行转码（带进度）
        if transcode_with_progress "$fpath" "$output_file" "$duration" "$current" "$total"; then
            ((success++)) || true
        else
            ((failed++)) || true
            failed_files+=("$fpath")
        fi
    done

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    local elapsed_min=$((elapsed / 60))
    local elapsed_sec=$((elapsed % 60))

    echo ""
    echo "━━━ 完成 ━━━"
    echo -e "  📊 总计：${total} 个文件"
    echo -e "  ${GREEN}✅ 成功：${success}${NC}"
    [[ $already_exists -gt 0 ]] && echo -e "  ${YELLOW}🔁 已存在（自动命名）：${already_exists}${NC}"
    [[ $failed -gt 0 ]] && echo -e "  ${RED}❌ 失败：${failed}${NC}"
    echo -e "  ⏱️ 总耗时：${elapsed_min}分${elapsed_sec}秒"
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

    # 分页浏览 + 用户选择
    declare -a selected_indices=()
    paginate_and_select selected_indices

    if [[ ${#selected_indices[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未选择任何文件${NC}"
        exit 0
    fi

    echo ""

    # 确认 + 转码
    confirm_and_transcode selected_indices
}

main "$@"
