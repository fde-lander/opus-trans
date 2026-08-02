# opus-trans 🐰

Termux Opus 转码器 — 将 Hi-Res FLAC 批量转码为 Opus 510kbps VBR（音质升级版 v1.2.2）

适合将 mora 购买嘅 Hi-Res FLAC（24bit/48-96kHz，每首 80-150MB）转码为便携嘅 Opus 文件（每首约 17MB，**最大听感**）。

---

## 功能

- 🎯 递归扫描子目录（按目录分组 A B C ...，q 留俾取消命令）
- 🎵 Opus 510kbps VBR（Opus 立体声硬顶）— 实测 480.9kbps，vs v1.1.0 实际只有 262-298kbps
- 🎚️ 自适应削波保护 — 源峰值 > -1.5dBFS 自动衰减到 -1.5dBFS（贴顶母带削波归零）
- 🪄 重采样自动探测 — soxr precision=28（VPS 用），Termux ffmpeg 8.1.2 soxr 有 bug 自动降级 swr
- 🖼️ 封面保留 — opusenc --picture 嵌入专辑封面（ffmpeg Ogg muxer 无 native cover）
- 🏷️ metadata 完整搬运 — 22 个 tags 保留 + ReplayGain 自动转 R128（RFC 7845）
- 📁 已存在 `.opus` 时自动命名 `song (2).opus`，绝不覆盖
- 🛡️ 原文件只读，不修改不删除
- 🔤 选择语法灵活：A1 / B1-B3 / B / A1,C2 / all
- ⌨️ 支持小写输入：`a1` 同 `A1` 一致
- 📊 智能文件大小显示（B/KB/MB/GB）+ 压缩率 + 封面标记
- 📈 进度显示：每首固定 4 行，零刷新（Termux 稳定）

---

## 前置要求

- **Termux**（F-Droid 版本，Play Store 版本已过时）
- **ffmpeg**：`pkg install ffmpeg`
- **opus-tools**（v1.2.0 新增依赖，提供 opusenc）：`pkg install opus-tools`

> ⚠️ v1.2.0 起转码链使用 opusenc（音质升级 + 封面 + 510k），未安装会报错并提示安装命令
> ⚠️ v1.2.2 已知问题：Termux ffmpeg 8.1.2 嘅 libsoxr 有 bug（Android NEON 编译），脚本会自动探测并降级到 swr（功能完整，仅重采样阻带抑制差约 6dB）。如需强制 swr，可设 `export OPUS_TRANS_FORCE_SWR=1`

---

## 安装

### 前置：传送脚本到 Termux

opus-trans.sh 喺你嘅开发机（VPS / 电脑）上，需要先传送到 Termux。

**方法 A：scp（推荐，需先启用 sshd）**

喺 Termux 启用 sshd：

    pkg install openssh
    passwd                  # 设置 Termux 密码
    sshd                    # 启动 sshd 守护进程
    ifconfig | grep 192.168 # 查 IP（例如 192.168.1.100）

喺 VPS 推送脚本：

    scp /home/hermes/workspace/opus-trans/opus-trans.sh u0_aXXX@192.168.1.100:~/

> `u0_aXXX` 系 Termux 嘅用户名（用 `whoami` 查 Termux 入面嘅当前用户名）

**方法 B：Termux 内置文件共享**

Termux 提供 `~/storage/shared/` 访问 Android 共享存储：

    # 喺 VPS 复制脚本到共享文件夹（通过其他方式：adb、syncthing、云盘）
    # 然后喺 Termux：
    cp /sdcard/Download/opus-trans.sh ~/.local/bin/opus-trans

**方法 C：直接喺 Termux 编辑**

如果只系短脚本，可以喺 Termux 用 nano/vim 直接编辑：

    nano ~/.local/bin/opus-trans
    # 粘贴脚本内容，保存
    chmod +x ~/.local/bin/opus-trans

### 步骤 1：安装到 ~/.local/bin

Termux 默认**冇** `~/.local` 目录，需要手动创建：

    mkdir -p ~/.local/bin
    cp opus-trans.sh ~/.local/bin/opus-trans
    chmod +x ~/.local/bin/opus-trans

### 步骤 2：确保 ~/.local/bin 喺 PATH 中

Termux 默认 PATH 系 `~/.local/bin` **唔喺度**，必须手动加。

**方法 A（推荐）**：喺 `~/.bashrc` 末尾加入

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

**方法 B**：喺 `~/.profile` 加入（适用于 login shell）

    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile

**步骤 3**：重启 Termux 或执行

    source ~/.bashrc

**步骤 4**：验证

    opus-trans --version
    # 应该输出：🎵 opus-trans v1.1.0 — Hi-Res FLAC → Opus 320k VBR

**如果仍然 `command not found`**：

检查 PATH 是否真系包含 ~/.local/bin：

    echo $PATH

睇下有没有 `~/.local/bin`（实际会展开为 `/data/data/com.termux/files/home/.local/bin`）。

如果冇，临时测试：

    export PATH="$HOME/.local/bin:$PATH"
    opus-trans --version

如果有效，永久加入 PATH（重做步骤 2）。

---

## 使用

    # 扫描当前目录
    cd ~/storage/music/某专辑
    opus-trans

    # 扫描指定目录
    opus-trans /sdcard/Music/某专辑

    # 显示版本
    opus-trans --version

    # 显示帮助
    opus-trans --help

---

## 选择语法（大小写均可）

| 输入 | 含义 |
|------|------|
| `a1` 或 `A1` | 选择 A 组第 1 首 |
| `b1-b3` | 选择 B 组第 1 到第 3 首 |
| `b` | 选择整个 B 组 |
| `a1,c2` | 混合选择多个 |
| `a,c` | 选择整个 A 组和 C 组 |
| `all` 或 `a` 或 `空 Enter` | 全部文件 |
| `q` | 取消 |

**有效组字母**（共 25 个）：A B C D E F G H I J K L M N O P R S T U V W X Y Z
（q 唔系有效组字母，因为 q 系取消命令）

**跳过规则**：
- `q1`、`q2` 等 q 开头嘅组合 → 静默跳过（用户嘅意图系想取消）
- `xyz` 等无效格式 → 报错退出
- `b99`（编号过大）→ 警告 + 跳过，让有效项继续处理
- `b1-b5` 但 `b3` 不存在 → 跳过 B3，转码 B1,B2,B4,B5

---

## 输出位置

转换后嘅 `.opus` 文件放喺**原文件同目录**，同名：

    某专辑/
    ├── song_A.flac      (原文件，唔郁)
    ├── song_A.opus      (新生成，约 10MB)
    ├── song_B.flac
    ├── song_B.opus
    └── Disc1/
        ├── track1.flac
        └── track1.opus

已存在 `.opus` 时：

    song.opus        (已有)
    song (2).opus    (新生成)
    song (3).opus    (再生成)

---

## 支持的输入格式

    flac  wav  ape  wv  mp3  m4a  aac  ogg  wma  aiff

---

## 常见问题

### Q: 为什么用 Opus 唔用 MP3？
A: Opus 喺任何 bitrate 都完胜 MP3。MP3 320kbps 仍可被 ABX 测试分辨，Opus 320kbps 已经达到「客观透明」。参考：r/audiophile、Hydrogenaudio 共识。

### Q: 为什么用 510kbps，唔用 320k？
A: v1.2.0 实测发现 v1.1.0 设定 320k 实际只有 262-298kbps（libopus VBR 自动下调）。510k 系 Opus 立体声硬顶，实测 480.9kbps，为主人金耳朵提供最大听感余量。文件体积约 17MB/首（v1.1.0 约 10MB）。

### Q: 原文件会被删吗？
A: 不会。FFmpeg 只读取输入文件，写入新文件。原 FLAC 完全唔郁。

### Q: 几时应该备份 FLAC？
A: Opus 系 lossy 转码，理论上唔可以逆向恢复。建议保留原始 FLAC 备份（例如云盘），Opus 只做便携副本。

### Q: v1.2.0 点解要用 opusenc？纯 ffmpeg 唔得咩？
A: 三个原因：
1. ffmpeg Ogg muxer 无 native cover art 支持（trac #4448 自 2014 未修），封面会丢
2. opusenc 可以做 --picture 嵌封面
3. opusenc 重采样质量不如 soxr，所以先 ffmpeg 预处理（soxr 重采样 + 自适应削波）再管道畀 opusenc 编码

### Q: 贴顶母带会唔会削波？
A: v1.2.0 内置自适应削波保护：源峰值 > -1.5dBFS 会自动衰减到 -1.5dBFS。贴顶母带（0dBFS）会轻微降低音量（约 1.5dB，多数人唔察觉），但消除全部削波失真。非贴顶源（峰值 ≤ -1.5dBFS）完全唔郁，音量 0dB 变化。

### Q: ReplayGain 标签会唔会保留？
A: 会，并且自动转成 R128 规范格式（RFC 7845）：REPLAYGAIN_TRACK_GAIN → R128_TRACK_GAIN。例如 -6.50 dB → R128_TRACK_GAIN=18560。

### Q: 唔记得 ~/.local/bin 嘅脚本喺边度？
A:

    ls ~/.local/bin/

### Q: 装完后 command not found？
A: 99% 系 PATH 问题。运行 `echo $PATH`，睇下有冇 `~/.local/bin`。冇嘅话重新执行步骤 2 同 3（确保 source ~/.bashrc 或重启 Termux）。

### Q: ~/.local 系默认存在嘅吗？
A: Termux **默认冇** ~/.local 目录。必须用 `mkdir -p ~/.local/bin` 手动创建。同埋 ~/.local/bin 默认唔喺 PATH，必须手动加。

### Q: 想卸载？
A:

    rm ~/.local/bin/opus-trans

### Q: v1.1.0 配色唔满意，想回退到 v1.0.4？
A: 有两种方法：

**方法 1：从备份回退（最简单）**

如果你有 opus-trans.sh.v1.0.4.bak 备份文件：

    cp opus-trans.sh.v1.0.4.bak ~/.local/bin/opus-trans
    chmod +x ~/.local/bin/opus-trans
    opus-trans --version
    # 应该输出：🎵 opus-trans v1.0.4

**方法 2：从 Git tag 回退**

如果你有 Git 仓库（~/workspace/opus-trans/）：

喺开发机（VPS）导出 v1.0.4 版本：

    cd ~/workspace/opus-trans
    git show v1.0.4:opus-trans.sh > opus-trans-v1.0.4.sh

然后 scp 传送到 Termux：

    scp opus-trans-v1.0.4.sh u0_aXXX@192.168.X.X:~/

喺 Termux 安装：

    cp opus-trans-v1.0.4.sh ~/.local/bin/opus-trans
    chmod +x ~/.local/bin/opus-trans
    opus-trans --version
    # 应该输出：🎵 opus-trans v1.0.4 — Hi-Res FLAC → Opus 320k VBR

---

## 更新日志

- **v1.1.0** — 列表美化：目录紫色粗体 + 编号鲜绿粗体（紫绿配色）
- **v1.0.4** — 智能跳过不存在的编号 + 警告；q 从有效组字母中排除
- **v1.0.3** — q 开头组合静默跳过；q 从编码中排除
- **v1.0.2** — UX 打磨（文件大小显示、彩色输出、错误信息详细化）
- **v1.0.0** — 首次发布