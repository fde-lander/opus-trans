#!/data/data/com.termux/files/usr/bin/bash
# opus-trans — Termux Opus 转码器
# 将 Hi-Res FLAC 批量转码为 Opus 320kbps VBR
# 作者: 超级猪兔兔 🐰
# 日期: 2026-08-02
# Spec: ~/.hermes/docs/superpowers/specs/2026-08-02-opus-trans-design.md

set -euo pipefail

# ── 常量 ──
readonly VERSION="1.2.3"
readonly BITRATE="510k"
readonly SOXR="aresample=48000:resampler=soxr:precision=28"
readonly SWR="aresample=48000"
readonly SUPPORTED_EXT="flac wav ape wv mp3 m4a aac ogg wma aiff"
# 注意：.opus 也在扫描范围内（可从 opus 转其他格式，但实际场景极少）

# ── 重采样器自动探测（v1.2.2）──
# ⚠️ Termux ffmpeg 8.1.2 嘅 libsoxr 有 bug（Android NEON 编译），一用就 segfault！
#   实测：soxr+s24le / soxr+s16le 都 crash，swr 全部正常（主人手机已验证）
#   方案：默认强制 swr（主人主要喺 Termux 用，写死 =1 唔使设环境变量）
#   如需改返 soxr：export OPUS_TRANS_FORCE_SWR=0 或改下面默认值
USE_SOXR=0   # 1=用 soxr, 0=用 swr
RESAMPLER="$SWR"

detect_resampler() {
    local test_file="$1"

    # 强制开关（默认 1 = 强制 swr，Termux 用户直接可用）
    # 主人要改返 soxr 时：export OPUS_TRANS_FORCE_SWR=0 再运行
    if [[ "${OPUS_TRANS_FORCE_SWR:-1}" == "1" ]]; then
        USE_SOXR=0
        RESAMPLER="$SWR"
        return
    fi

    # 非强制模式：自动探测 soxr 可用性（VPS 等 soxr 正常环境）
    local tmp_base="${TMPDIR:-/tmp}"
    [[ ! -d "$tmp_base" ]] && tmp_base="$HOME"
    local test_out="$tmp_base/.opus-trans-soxr-test.$$.wav"

    # 用目标文件跑 0.3 秒 soxr 测试
    # ⚠️ 靠「输出文件有数据」判断会误判（segfault 前可能已输出 >100KB）
    #   改为检测 ffmpeg 退出码（segfault = 139）+ if 包裹避免 set -e 终止
    rm -f "$test_out" 2>/dev/null || true
    if ffmpeg -v error -i "$test_file" -t 0.3 \
        -af "$SOXR" -c:a pcm_s16le -f wav - 2>/dev/null > "$test_out"; then
        if [[ -s "$test_out" ]]; then
            USE_SOXR=1
            RESAMPLER="$SOXR"
        else
            USE_SOXR=0
            RESAMPLER="$SWR"
            echo -e "${YELLOW}⚠️ 检测到 soxr 无输出（可能 ffmpeg bug），已自动改用 swr 重采样${NC}"
        fi
    else
        # 退出码非零（139=segfault）→ soxr 唔可用
        USE_SOXR=0
        RESAMPLER="$SWR"
        echo -e "${YELLOW}⚠️ 检测到 soxr 不可用（Termux ffmpeg bug），已自动改用 swr 重采样${NC}"
        echo -e "${YELLOW}  音质提示：swr 比 soxr 阻带抑制差约 6dB，但功能完整（510k/封面/tags/削波保护）${NC}"
    fi
    rm -f "$test_out" 2>/dev/null || true
}

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
BOLDGREEN='\033[1;32m'  # 编号用 — 鲜绿粗体（醒目，唔撞文件名/大小/目录）
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
    echo -e "${CYAN}🎵 opus-trans${NC} ${BOLD}v${VERSION}${NC} — Hi-Res FLAC → Opus 510k VBR"
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

check_opusenc() {
    if ! command -v opusenc &>/dev/null; then
        echo -e "${RED}❌ 错误: opusenc 未安装${NC}"
        echo ""
        echo "v1.2.0 起转码链使用 opusenc（音质升级，支持封面 + 510k）"
        echo "请先安装 opus-tools:"
        echo "  pkg install opus-tools"
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

        echo -e "  ${BOLDGREEN}${grp}${num}.${NC} ${fname}  ${CYAN}$(file_size_human "$size")${NC}${exists_marker}"
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

# ── v1.2.0 音质升级：位深检测 ──
# 检测源音频位深（24bit FLAC 的 container 系 s32，必须用 bits_per_raw_sample）
detect_depth() {
    local input_file="$1"
    local src_fmt src_raw src_bits depth

    src_fmt=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_fmt -of default=nw=1:nk=1 "$input_file")
    src_raw=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_raw_sample -of default=nw=1:nk=1 "$input_file")
    src_bits=$(ffprobe -v error -select_streams a:0 -show_entries stream=bits_per_sample -of default=nw=1:nk=1 "$input_file")

    # 浮点格式（flt/dbl）用 bits_per_sample；整数格式用 bits_per_raw_sample
    if [[ "$src_fmt" == *"flt"* || "$src_fmt" == *"dbl"* ]]; then
        depth="$src_bits"
    else
        depth="$src_raw"
    fi

    # N/A/空/0 → 默认 24（罕见情况保守处理）
    [[ "$depth" == "N/A" || "$depth" == "" || "$depth" == "0" ]] && depth="24"

    echo "$depth"
}

# ── v1.2.0 音质升级：位深 → 管道编码器映射 ──
depth_to_pipe_fmt() {
    case "$1" in
        16) echo "pcm_s16le" ;;
        24) echo "pcm_s24le" ;;
        32) echo "pcm_f32le" ;;
        *)  echo "pcm_s24le" ;;
    esac
}

# ── v1.2.0 音质升级：抽封面 ──
# 从 FLAC 抽 attached_pic → 临时文件；无封面时返回空
# ⚠️ Termux 冇 /tmp！必须用 ${TMPDIR:-/tmp} 动态检测 + fallback
extract_cover() {
    local input_file="$1"
    local tmp_base="${TMPDIR:-/tmp}"
    # Termux 通常有 $PREFIX/tmp，Linux 有 /tmp；都冇就 fallback 到 $HOME
    if [[ ! -d "$tmp_base" ]]; then
        tmp_base="$HOME"
    fi
    mkdir -p "$tmp_base" 2>/dev/null || true
    # ⚠️ 必须加 .png 扩展名，否则 ffmpeg 无法识别输出格式（关键陷阱 3）
    local tmpcover
    tmpcover="$(mktemp "$tmp_base/opus-trans-cover.XXXXXX").png" || tmpcover="$HOME/.opus-trans-cover.$$.png"

    # 从 FLAC 抽封面（若有）；-v error 对封面抽取没问题（唔需要 astats 输出）
    ffmpeg -v error -i "$input_file" -map 0:v -c:v copy -y "$tmpcover" 2>/dev/null || true
    # 成功标志：文件存在且 > 0 字节（无封面时 ffmpeg 报 "Stream map matches no streams" 但退出码可能仍 0）
    if [[ -s "$tmpcover" ]]; then
        echo "$tmpcover"
    else
        rm -f "$tmpcover"
        echo ""
    fi
}

# ── v1.2.0 音质升级：扫峰值（决定衰减量）──
# ⚠️⚠️ 关键陷阱：绝对唔可以加 -v error！
#   astats 嘅统计输出行喺 stderr，-v error 会连「Peak level dB」一齐吞掉，PEAK 变空
# ⚠️ v1.2.0 hotfix：合并封面抽取 + 峰值扫描到一次 ffmpeg 调用（减少启动次数，扫描大文件更快出结果）
# ⚠️ 大文件（24/192）完整解码先出峰值，加 -t 180 限制扫描前 3 分钟（J-pop 峰值通常喺前段）
#   如果 3 分钟峰值 ≤ -1.5 → 全曲大概率唔需要保护；如果 > -1.5 → 用扫描到嘅峰值保守计算
scan_peak() {
    local input_file="$1"
    local peak

    peak=$(ffmpeg -i "$input_file" -t 180 \
        -af "aformat=sample_fmts=flt,astats=metadata=1" \
        -f null - 2>&1 | grep -iE "Peak level dB" | head -1 | grep -oE '\-?[0-9]+\.[0-9]+' || true)

    # 扫峰值失败 → 保守返回 -1.5（按最坏情况衰减）
    if [[ -z "$peak" ]]; then
        echo "-1.5"
    else
        echo "$peak"
    fi
}

# ── v1.2.0 音质升级：计算衰减量（PAD）──
# 规则：源峰值 P > -1.5 dBFS → 衰减到 -1.5 dBFS（PAD 系负数）
#      源峰值 P ≤ -1.5 dBFS → 唔衰减（PAD=0）
# ⚠️ 曾犯错误：写成 PAD = P + 1.5（正数）= 增益 1.5dB，令削波更严重！
# ⚠️ 方波极端实测：源峰值 -0.026 → PAD=-1.47 仍残留 18 个削波样本（0.0023%）
#   加下限保护：PAD 至少 -1.5dB（杜绝方波等极端瞬态残余削波）
calc_pad() {
    local peak="$1"
    awk -v p="$peak" 'BEGIN {
        if (p > -1.5) {
            pad = -(p + 1.5)
            # 下限保护：PAD 最小 -1.5dB（峰值越接近 0dBFS 越要留足余量）
            if (pad > -1.5) pad = -1.5
            printf "%.2f", pad
        } else {
            printf "0"
        }
    }'
}

# ── v1.2.0 音质升级：metadata 搬运 ──
# ⚠️ 实测发现：opusenc 从 WAV 管道输入时唔会自动继承源 tags（输出 format_tags 为空）
#   必须手动将源 tags 转成 opusenc --comment 参数
# ⚠️ ReplayGain 规范（RFC 7845）：REPLAYGAIN_* → R128_TRACK_GAIN / R128_ALBUM_GAIN
#   转换公式：R128 = round((66 - RG_GAIN) * 256)
# ⚠️ 用全局数组 META_ARGS 传递（避免子进程/字符串解析问题）
declare -a META_ARGS=()

build_metadata_args() {
    local input_file="$1"
    local tag_key tag_val rg_val r128_val
    META_ARGS=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # 去掉 TAG: 前缀，拆 key=value（第一个 = 分割，value 可含 =）
        tag_key=$(echo "$line" | sed 's/^TAG://' | cut -d= -f1)
        tag_val=$(echo "$line" | sed 's/^TAG://' | cut -d= -f2-)
        [[ -z "$tag_key" || -z "$tag_val" ]] && continue

        case "$tag_key" in
            # ReplayGain → R128 转换（RFC 7845 规范）
            REPLAYGAIN_TRACK_GAIN)
                rg_val=$(echo "$tag_val" | grep -oE '[-0-9.]+' | head -1)
                if [[ -n "$rg_val" ]]; then
                    r128_val=$(awk -v rg="$rg_val" 'BEGIN { printf "%.0f", (66 - rg) * 256 }')
                    META_ARGS+=("--comment" "R128_TRACK_GAIN=$r128_val")
                fi
                ;;
            REPLAYGAIN_ALBUM_GAIN)
                rg_val=$(echo "$tag_val" | grep -oE '[-0-9.]+' | head -1)
                if [[ -n "$rg_val" ]]; then
                    r128_val=$(awk -v rg="$rg_val" 'BEGIN { printf "%.0f", (66 - rg) * 256 }')
                    META_ARGS+=("--comment" "R128_ALBUM_GAIN=$r128_val")
                fi
                ;;
            # 跳过重复的 REPLAYGAIN_PEAK（R128 无需 peak）+ 编码器自带 tag
            REPLAYGAIN_TRACK_PEAK|REPLAYGAIN_ALBUM_PEAK|encoder|ENCODER|tool)
                ;;
            *)
                # 通用 tag 搬运（空值跳过）
                META_ARGS+=("--comment" "${tag_key}=${tag_val}")
                ;;
        esac
    done < <(ffprobe -v error -show_entries format_tags -of default=nw=1 "$input_file" 2>/dev/null || true)
}

transcode() {
    local input_file="$1"
    local output_file="$2"

    # ── 1. 抽封面（若有）──
    local cover_path
    cover_path=$(extract_cover "$input_file")
    local has_cover=0
    [[ -n "$cover_path" ]] && has_cover=1

    # ── 2. 扫峰值（决定衰减量）──
    # ⚠️ v1.2.1 性能优化：优先用 confirm_and_transcode 已扫描嘅全局值
    #    （之前 scan_peak 被调用两次 = 大文件完整解码两次，超慢！）
    local peak pad
    if [[ -n "${PEAK_SCANNED_PEAK:-}" ]]; then
        peak="$PEAK_SCANNED_PEAK"
        pad="$PEAK_SCANNED_PAD"
    else
        peak=$(scan_peak "$input_file")
        pad=$(calc_pad "$peak")
    fi

    # ── 3. 智能位深（16→s16le / 24→s24le / 32→f32le）──
    local src_depth pipe_fmt
    src_depth=$(detect_depth "$input_file")
    pipe_fmt=$(depth_to_pipe_fmt "$src_depth")

    # ── 3.5 metadata 搬运（ReplayGain → R128）──
    # ⚠️ 实测：opusenc 唔会自动继承 WAV 管道嘅源 tags，必须手动传 --comment
    build_metadata_args "$input_file"

    # ── 3.6 组装 opusenc 参数数组（避免空字符串参数坑）──
    local -a enc_args=(--bitrate 510 --music --comp 10)
    [[ ${#META_ARGS[@]} -gt 0 ]] && enc_args+=("${META_ARGS[@]}")
    [[ "$has_cover" == "1" ]] && enc_args+=(--picture "$cover_path")

    # ── 4. 转码（v1.2.1：RESAMPLER 已喺启动时探测，唔使每次试错）──
    # ⚠️ Termux ffmpeg 8.1.2 soxr 有 bug 会 segfault → detect_resampler 已自动切 swr
    #    L1: RESAMPLER + PIPE_FMT（完整音质）
    #    L2: RESAMPLER + s16le（降位深管道，超罕见）
    local vol_filter=""
    [[ "$pad" != "0" ]] && vol_filter="volume=${pad}dB,"

    local encode_ok=0
    local ffmpeg_status opusenc_status pipe_status
    local -a ff_args

    # 尝试 L1（完整音质）
    ff_args=(-v error -i "$input_file" -af "${vol_filter}${RESAMPLER}" -c:a "$pipe_fmt" -f wav -)
    ffmpeg "${ff_args[@]}" 2>/dev/null | opusenc "${enc_args[@]}" - "$output_file" 2>/dev/null
    pipe_status=("${PIPESTATUS[@]}")
    ffmpeg_status=${pipe_status[0]}
    opusenc_status=${pipe_status[1]}
    if [[ $ffmpeg_status -eq 0 && $opusenc_status -eq 0 ]]; then
        encode_ok=1
    else
        echo -e "       ${YELLOW}⚠️ L1 失败 (${RESAMPLER}+${pipe_fmt})，降级到 L2 (s16le)${NC}"
        rm -f "$output_file" 2>/dev/null || true
        # L2: RESAMPLER + s16le
        ff_args=(-v error -i "$input_file" -af "${vol_filter}${RESAMPLER}" -c:a pcm_s16le -f wav -)
        ffmpeg "${ff_args[@]}" 2>/dev/null | opusenc "${enc_args[@]}" - "$output_file" 2>/dev/null
        pipe_status=("${PIPESTATUS[@]}")
        ffmpeg_status=${pipe_status[0]}
        opusenc_status=${pipe_status[1]}
        if [[ $ffmpeg_status -eq 0 && $opusenc_status -eq 0 ]]; then
            encode_ok=1
        else
            echo -e "       ${YELLOW}⚠️ L2 失败 (s16le)，降级到 L3 (纯 ffmpeg libopus)${NC}"
            rm -f "$output_file" 2>/dev/null || true
            # L3: 纯 ffmpeg libopus（最保守，封面丢）
            ffmpeg -v error -i "$input_file" \
                -c:a libopus -b:a "$BITRATE" -vbr on \
                -map_metadata 0 \
                "$output_file" 2>/dev/null
            if [[ $? -eq 0 && -s "$output_file" ]]; then
                encode_ok=1
            fi
        fi
    fi

    # ── 5. 清理封面临时文件 ──
    [[ -n "$cover_path" ]] && rm -f "$cover_path"

    # ── 6. 结果 ──
    [[ $encode_ok -eq 1 ]] && return 0 || return 1
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

        echo -e "  ${BOLDGREEN}${grp}${num}.${NC} ${fname}${exists_marker}"
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
    local cover_ok=0
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

        # ── v1.2.0：固定 4 行进度（Termux 铁律：零刷新，印完即定）──
        # 第 1 行：文件标题
        echo -e "  [${current}/${total}] ${relpath}${name_note}"

        # 第 2 行：峰值 + 衰减信息（预先扫描，用于显示）
        # ⚠️ v1.2.1 性能优化：扫描一次存入全局，transcode() 直接复用，唔使重复解码
        local peak pad
        peak=$(scan_peak "$fpath")
        pad=$(calc_pad "$peak")
        PEAK_SCANNED_PEAK="$peak"
        PEAK_SCANNED_PAD="$pad"
        if [[ "$pad" == "0" ]]; then
            echo -e "       峰值 ${peak} dBFS → 无需保护"
        else
            echo -e "       峰值 ${peak} dBFS → 应用 ${pad}dB 保护"
        fi

        # 第 3 行：转码中（实际执行）
        # v1.2.3: 显示实际使用嘅重采样器（swr or soxr）
        if [[ "$USE_SOXR" == "1" ]]; then
            echo -e "       转码中 (soxr → opus 510k)..."
        else
            echo -e "       转码中 (swr → opus 510k)..."
        fi

        # 执行转码
        local in_size out_size
        in_size=$(stat -c%s "$fpath" 2>/dev/null || stat -f%z "$fpath" 2>/dev/null || echo 0)
        if transcode "$fpath" "$output_file"; then
            # 验证输出
            if [[ -f "$output_file" ]] && [[ $(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0) -gt 0 ]]; then
                out_size=$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file" 2>/dev/null || echo 0)
                # 压缩率
                local ratio=0
                if [[ $in_size -gt 0 ]]; then
                    ratio=$(( (in_size - out_size) * 100 / in_size ))
                    [[ $ratio -lt 0 ]] && ratio=0
                fi
                # 封面检测（v1.2.0）
                local cover_mark=""
                if command -v opusinfo &>/dev/null; then
                    if opusinfo "$output_file" 2>/dev/null | grep -q "METADATA_BLOCK_PICTURE"; then
                        cover_mark="  封面 ✓"
                        ((cover_ok++)) || true
                    else
                        cover_mark="  封面 ✗"
                    fi
                fi
                # 第 4 行：结果（大小 + 压缩率 + 封面）
                echo -e "       ${CYAN}$(file_size_human "$in_size")${NC} → ${CYAN}$(file_size_human "$out_size")${NC}  (压缩 ${ratio}%)${cover_mark}"
                if [[ -z "$name_note" ]]; then
                    ((success++)) || true
                fi
            else
                echo -e "       ${RED}❌ 输出验证失败${NC}"
                ((failed++)) || true
                failed_files+=("$fpath")
            fi
        else
            echo -e "       ${RED}❌ 转码失败${NC}"
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
    [[ $cover_ok -gt 0 ]] && echo -e "  ${CYAN}🖼️ 封面保留：${cover_ok}${NC}"
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
    check_opusenc
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

    # v1.2.1: 探测 soxr 可用性（用第一个选中文件测试，Termux 唔得就全 session 用 swr）
    local first_file="${FILE_PATHS[${selected_indices[0]}]}"
    detect_resampler "$first_file"

    # 确认 + 转码
    confirm_and_transcode selected_indices
}

main "$@"
