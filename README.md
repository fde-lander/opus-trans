# opus-trans 🐰

> **Hi-Res FLAC / WAV → Opus 510kbps VBR transcoder for Termux (Android) & Linux**
> 手機 Termux / Linux 高音質轉碼神器 — 將 Hi-Res FLAC / WAV 批量轉碼為 Opus 510kbps VBR（最大聽感）

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Termux / Linux](https://img.shields.io/badge/Platform-Termux%20%2F%20Linux-blue.svg)]()
[![Version: v1.2.4](https://img.shields.io/badge/Version-v1.2.4-green.svg)]()
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)]()

A single-file Bash script that batch-transcodes **Hi-Res FLAC / WAV** (and other lossless/lossy formats) into high-quality **Opus 510kbps VBR** files — perfect for music bought from **mora** (Hi-Res FLAC 24bit/48-96kHz, 80-150MB per track) that you want as portable, phone-friendly copies (~15MB per track, **maximum audible quality**).

Designed and tested on **Termux (Android)**, also works on **Debian / other Linux** desktops & servers. No macOS/Windows support (untested).

---

## ✨ Features

- 🎯 **Recursive directory scanning** — groups files by folder (A, B, C...), `q` reserved for quit
- 🎵 **Opus 510kbps VBR** (Opus stereo hard ceiling) — measured 480.9kbps actual, vs 262-298kbps on old 320k setting
- 🎚️ **Adaptive clipping protection** — source peak > -1.5dBFS is auto-attenuated to -1.5dBFS (eliminates clipping from hot-mastered tracks)
- 🪄 **swr resampling by default (v1.2.3)** — Termux ffmpeg 8.1.2 has a **libsoxr bug (segfault)**, swr is the stable default
- 🖼️ **Album art preserved** — embedded via `opusenc --picture` (ffmpeg Ogg muxer has no native cover support)
- 🏷️ **Full metadata migration** — 22 tags preserved + ReplayGain auto-converted to R128 (RFC 7845)
- 📁 **Never overwrites** — existing `.opus` gets auto-renamed to `song (2).opus`
- 🛡️ **Source files untouched** — read-only, never modified or deleted
- 🔤 **Flexible selection syntax** — `A1` / `B1-B3` / `B` / `A1,C2` / `all` (case-insensitive)
- 📊 **Smart file size display** (B/KB/MB/GB) + compression ratio + cover-art marker
- 📈 **Progress display** — fixed 4 lines per track, zero refresh (Termux-stable)

---

## 📥 Installation

### Termux

**Step 1 — Install dependencies**

    pkg install ffmpeg opus-tools

**Step 2 — Copy the script to `~/.local/bin`**

    mkdir -p ~/.local/bin
    cp opus-trans.sh ~/.local/bin/opus-trans
    chmod +x ~/.local/bin/opus-trans

**Step 3 — Make sure `~/.local/bin` is in PATH**

Termux does NOT include `~/.local/bin` in PATH by default. Add it:

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc

**Step 4 — Verify**

    opus-trans --version
    # 🎵 opus-trans v1.2.4 — Hi-Res FLAC → Opus 510k VBR

> **Getting the script onto your phone**: use `scp` (after `pkg install openssh` + `sshd`), or copy via Termux's `~/storage/shared/` (Android shared storage), or download directly from the [Releases page](https://github.com/fde-lander/opus-trans/releases).

### Debian / Ubuntu / Linux

    sudo apt install ffmpeg opus-tools
    sudo cp opus-trans.sh /usr/local/bin/opus-trans
    sudo chmod +x /usr/local/bin/opus-trans

### Other Linux distros

    # Replace with your package manager
    sudo dnf install ffmpeg opus-tools      # Fedora
    sudo pacman -S ffmpeg opus-tools        # Arch

---

## 🚀 Usage

    # Scan current directory
    cd ~/storage/music/SomeAlbum
    opus-trans

    # Scan a specific directory
    opus-trans /sdcard/Music/SomeAlbum

    # Show version / help
    opus-trans --version
    opus-trans --help

### Selection syntax (case-insensitive)

| Input        | Meaning                              |
|--------------|--------------------------------------|
| `a1` / `A1`  | File 1 in group A                    |
| `b1-b3`      | Files 1 to 3 in group B              |
| `b`          | Entire group B                       |
| `a1,c2`      | Multiple selections                  |
| `a,c`        | Entire groups A and C                |
| `all` / empty | All files                           |
| `q`          | Quit                                 |

Valid group letters: `A B C D E F G H I J K L M N O P R S T U V W X Y Z` (25 letters; `q` is reserved for quit).

**Skip rules**: `q1`/`q2` → silently skipped; invalid format like `xyz` → error; `b99` (out of range) → warning + skip; `b1-b5` with missing `b3` → transcode 1,2,4,5.

---

## 📁 Output

Transcoded `.opus` files are written **next to the source files**:

    SomeAlbum/
    ├── song_A.flac      (source, untouched)
    ├── song_A.opus      (new, ~15MB)
    └── Disc1/
        ├── track1.flac
        └── track1.opus

Existing `.opus` files are never overwritten:

    song.opus        (existing)
    song (2).opus    (new)

### Supported input formats

    flac  wav  ape  wv  mp3  m4a  aac  ogg  wma  aiff

---

## 🔧 How it works

The v1.2.x pipeline uses a **two-stage chain** for maximum quality:

    Source (FLAC/WAV)
        │  ffmpeg preprocessing (one pass):
        │    • extract cover art      → temp file
        │    • scan peak level        → adaptive clip protection
        │    • smart bit depth        → 24bit / 16bit auto
        │    • swr/soxr resampling    → 48kHz
        ▼
    WAV pipe (stdout)
        │  opusenc 510k VBR:
        │    • --picture embeds cover art
        │    • --comment carries all metadata (22 tags)
        │    • ReplayGain → R128 conversion (RFC 7845)
        ▼
    Output: song.opus

**Why opusenc instead of plain ffmpeg?** The ffmpeg Ogg muxer has no native cover-art support (trac #4448, unfixed since 2014), so covers would be lost. `opusenc --picture` embeds them properly. ffmpeg handles preprocessing (resampling + clip protection), opusenc handles encoding.

---

## 🔄 Resampler selection

The script defaults to **swr** (stable everywhere). Termux ffmpeg 8.1.2's libsoxr has a bug that segfaults on Android NEON builds — so swr is the safe default.

**On Debian / other Linux** (where soxr works fine), you can switch to soxr for slightly better anti-aliasing (~6dB better stopband). Two ways:

**Option A — edit the constant (recommended, persistent):**

Open `opus-trans.sh` and change line ~23:

    # Before:
    USE_SOXR=0   # 1=use soxr, 0=use swr
    # After:
    USE_SOXR=1   # 1=use soxr, 0=use swr

Then copy the modified file to `~/.local/bin/opus-trans` (or `/usr/local/bin/opus-trans`).

**Option B — environment variable (temporary):**

    export OPUS_TRANS_FORCE_SWR=0
    opus-trans

> ℹ️ `OPUS_TRANS_FORCE_SWR=1` (default) forces swr without probing. `=0` enables auto-detection: the script probes soxr once on the first selected file (0.3s test) and falls back to swr if it crashes or produces no output.

---

## ❓ FAQ

**Q: Why Opus instead of MP3?**
A: Opus beats MP3 at every bitrate. MP3 320kbps is still distinguishable in ABX tests; Opus 320kbps is objectively transparent. (r/audiophile, Hydrogenaudio consensus.)

**Q: Why 510kbps instead of 320k?**
A: v1.2.0 measurement showed the old "320k" setting actually produced only 262-298kbps (libopus VBR auto-downshifts). 510k is the Opus stereo hard ceiling; measured 480.9kbps actual — maximum headroom for critical listening. File size ~15MB/track vs ~10MB at old 320k.

**Q: Are my source files modified?**
A: No. ffmpeg only reads inputs; the original FLAC/WAV is never touched.

**Q: Should I keep the FLAC backups?**
A: Yes. Opus is lossy — irreversible. Keep your original FLAC as the archive copy; Opus is the portable convenience copy.

**Q: Will hot-mastered (0dBFS) tracks clip?**
A: No. v1.2.0+ has adaptive clipping protection: if source peak > -1.5dBFS, it's auto-attenuated to -1.5dBFS. Hot masters get a slight volume reduction (~1.5dB, barely noticeable) but zero clipping distortion. Normal tracks (peak ≤ -1.5dBFS) are untouched.

**Q: Is ReplayGain preserved?**
A: Yes, auto-converted to R128 (RFC 7845): e.g. `REPLAYGAIN_TRACK_GAIN=-6.50 dB` → `R128_TRACK_GAIN=18560`.

**Q: Why does Termux use swr but my Linux PC can use soxr?**
A: Termux's ffmpeg 8.1.2 is compiled with a buggy Android NEON libsoxr that segfaults. Debian's ffmpeg 7.1.3 has a working soxr. The script detects platform and install commands automatically; resampler defaults to swr everywhere for consistency.

**Q: Can I uninstall?**
A: Just remove the script:

    rm ~/.local/bin/opus-trans     # Termux
    sudo rm /usr/local/bin/opus-trans   # Linux

---

## 📜 Changelog

### v1.2.4 (2026-08-02) — Public release prep 🌍
- **Internationalized README** — English-first with Traditional Chinese summary, GitHub-flavored (badges, structured docs, FAQ, changelog)
- **Platform-aware install hints** — the script now detects Termux / Debian / other Linux and shows the correct dependency install command (`pkg install` vs `sudo apt install` vs your package manager)
- **MIT License** added
- Cross-platform positioning: designed & tested on Debian, primary use on Termux (Android); Linux desktop/server supported; macOS/Windows untested

### v1.2.3 (2026-08-02) — Stable release ✅
- **Default swr resampling** — Termux users get stable runs out of the box (no env vars needed)
- **Progress display sync** — now shows the actual resampler in use (swr/soxr), previously always showed "soxr" misleadingly
- Master-verified on Termux: better sound, cover art present, 27MB → 15MB (42% compression)
- Latest tag: `f60825b`

### v1.2.2 (2026-08-02) — Fix
- **Probe logic fix** — now detects ffmpeg exit code (139=SIGSEGV) instead of output-file size (segfault could produce >100KB before crash → false "soxr available")
- **`OPUS_TRANS_FORCE_SWR` env var** added as a master switch
- Test duration reduced 0.5s → 0.3s

### v1.2.1 (2026-08-02) — Hotfix
- **Termux ffmpeg soxr segfault auto-fallback** — soxr crash on Android NEON builds → auto-detect and switch to swr
- **`/tmp` fix** — Termux has no `/tmp`; falls back to `$HOME`
- Performance optimization

### v1.2.0 (2026-08-02) — Major audio quality upgrade 🎉
- **510kbps VBR** (Opus stereo ceiling; measured 480.9kbps) vs 262-298kbps before
- **soxr resampling** for preprocessing (with swr fallback)
- **Adaptive clipping protection** (-1.5dBFS ceiling)
- **Cover art via opusenc `--picture`**
- **Full metadata migration** — 22 tags + ReplayGain→R128 (RFC 7845)
- **opus-tools dependency** added (provides opusenc)

### v1.1.0 — List beautification
- Directory names in magenta bold + numbering in bright green bold

### v1.0.4 — Selection parser hardening
- Smart skip for nonexistent numbers + warnings
- `q` excluded from valid group letters

### v1.0.3 — UX
- `q`-prefixed combos silently skipped; `q` excluded from encoding

### v1.0.2 — UX polish
- File size display, colored output, detailed error messages

### v1.0.0 — Initial release

---

## 📄 License

[MIT](LICENSE) © 2026 超级猪兔兔 🐰

---

## 🌏 繁體中文摘要

**opus-trans** 係一款單文件 Bash 腳本，專門喺 **手機 Termux** 上面，將 mora 購買嘅 **Hi-Res FLAC / WAV**（24bit/48-96kHz，每首 80-150MB）批量轉碼為高音質 **Opus 510kbps VBR** 文件（每首約 15MB，**最大聽感**）。

**特點**：Opus 510k 立體聲硬頂（實測 480.9kbps）、自適應削波保護、封面保留、22 個 metadata tags 完整搬運、ReplayGain→R128、永不覆蓋原檔、原檔只讀。

**安裝（Termux）**：
- `pkg install ffmpeg opus-tools`
- 複製 `opus-trans.sh` 到 `~/.local/bin/opus-trans` 並 `chmod +x`
- `~/.local/bin` 加落 PATH（`.bashrc`）

**安裝（Debian / Linux）**：
- `sudo apt install ffmpeg opus-tools`
- 複製到 `/usr/local/bin/opus-trans` 並 `chmod +x`

**使用**：`opus-trans`（掃描當前目錄）或 `opus-trans /sdcard/Music/某專輯`

**Debian 想用 soxr（音質略好）**：改 `opus-trans.sh` 第 23 行 `USE_SOXR=0` → `USE_SOXR=1`，再複製到安裝位置。Termux 用戶**唔好**改（ffmpeg 8.1.2 嘅 soxr 有 bug 會 crash）。

**注意**：開發同測試喺 Debian 系統完成，實際主力用喺 Termux；Linux 桌面/伺服器都支援。macOS / Windows 未測試，暫不支援。

