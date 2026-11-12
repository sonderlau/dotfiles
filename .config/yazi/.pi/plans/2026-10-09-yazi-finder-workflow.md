# Yazi 日常替代 Finder

目标：在 Ghostty 里把 yazi 用顺手。配色跟终端暖色暗底对齐，忘了键位能查，复制/解压/开 agent/看 PDF 都有固定入口。

## 现状

配置在 `~/.config/yazi`，版本 **26.9.1**。没有 `yazi.toml`，预览、打开规则、解压都走内置默认。

- `theme.toml` 几乎是空的：`[flavor].use = ""`，只改了状态栏三种模式（黑字 + blue/red/yellow 底）。
- Ghostty 主题是 `warm-burnout-dark`：背景 `#1a1510`，前景 `#bfbdb6`，选区 `#33393a`，ANSI 亮白是 `#ffffff`，透明度 0.85。yazi 默认文件名、边框、高亮大量用 ANSI `white` / `bright white`，叠在这套调色板上会发白、和背景糊在一起。状态栏那三行黑字在亮蓝/亮黄底上也会刺眼。
- 按键总览已经绑了：`~` 和 `F1` → `help`。help 里可以按 `f` 过滤。keymap 里每条都有 `desc`，所以 help 能列出。
- 复制已经是 vim 式：空格多选（或 `v` 可视模式）→ `y` 复制 / `x` 剪切 → 切目录 → `p` 粘贴。回上一个目录是 `H`（`L` 前进）。这套不用改行为，只需要写进一份自己的速查，避免和「复制路径」的 `c` 搞混。
- 解压：内置 opener 对 zip/tar/7z 等已经是 `ya pub extract`，本机有 `7zz`。缺的是**不经过打开菜单的快捷键**，以及 help 里看不到默认 opener（opener 不在 keymap 里）。
- Agent：PATH 上有 `pi`、`claude`、`codex`、`opencode`、`gemini`。`~/.local/bin/agent` 是 Cursor 的 CLI，不放进菜单。
- PDF：预览器已经是内置 `pdf`（`pdftoppm` 转成一页 JPEG 再显示）。`pdftoppm` 已安装。Yazi 26.9 会把 Ghostty 认成 kitty 图形协议，**右栏预览应当直接出图**，不必开 Acrobat。`I` 已经绑了 `qlmanage -p`（macOS Quick Look，会弹系统窗口）。Acrobat 多半是按了 `Enter`（`open`，走系统默认 PDF 应用），不是预览栏本身。

## 改哪些文件

### 1. `theme.toml` — 对齐 warm-burnout

不用 flavor（`package.toml` 里 flavor 依赖是空的，也不去拉第三方主题）。把 Ghostty 那组色写进 yazi 的 hex：

| 用途 | 色 |
|---|---|
| 普通文件名 | `#bfbdb6` |
| 目录 | `#fdb04c` |
| 符号链接 | `#93e2c8` |
| 可执行 | `#70bf56` |
| 选中行 | 底 `#33393a`，字 `#bfbdb6` |
| 光标行 | 底 `#2a2420`，字 `#f5c56e` |
| 边框 | `#686868`，不要白 |
| 状态栏 normal/select/unset | 深色字 `#1a1510` + 底 `#4fbfff` / `#f06b73` / `#fdb04c` |

同时改 `[filetype]` 规则，覆盖默认里「普通文件 = white」那条。`syntect_theme` 保持空（代码高亮继续用内置）。`init.lua` 里 git 的 blue/red 不动，和这套不冲突。

### 2. `keymap.toml` — 补入口，不重排现有键

`prepend_keymap` 里加（不覆盖默认，只占现在空着的键）：

- `e`：对选中的压缩包执行 `ya pub extract --list`，解压到**当前目录**（和内置 opener 同一条命令）。
- `g` `a`：弹出 agent 菜单（见下）。
- help 继续用 `~` / `F1`，不改键。在 `~` 那条的 `desc` 上写清楚「按键一览」，方便自己在 help 里搜到。

复制流程不改键：`Space`/`v` → `y` → 换目录 → `p`，回来按 `H`。

### 3. `init.lua` — agent 选择菜单

一个小函数，不装新插件。`g a` 时用 `ya.which` 列出：

1. pi
2. claude
3. codex
4. opencode
5. gemini

选中后 `shell` 以 `--block` 在当前目录启动（yazi 的 shell 默认 cwd 就是当前面板目录），退出回到 yazi。菜单本身也算「忘了有哪些 agent」时的提示。

### 4. `yazi.toml` — 只加 PDF 这一段

新建文件，只写 `[plugin.prepend_previewers]`，把 `application/pdf` 指到内置 `pdf`。这样即使以后默认规则变了，右栏仍然走 `pdftoppm`，而不是系统打开。不复制整份默认配置，避免和以后的 yazi 升级打架。

`Enter` 仍是系统打开（Acrobat）。看内容用右栏；要 macOS 原生预览按已有的 `I`（Quick Look）。不把 `Enter` 改成预览，避免打不开需要编辑器的文件。

### 5. 速查

在 `keymap.toml` 顶部注释里放 15 行常用键，不另建会被忘掉的 markdown：

- `~` / `F1` 按键一览，`f` 过滤
- 多选复制：`Space` 或 `v`，`y` 复制，`x` 剪切，`p` 粘贴，`H` 回上一目录
- `e` 解压到当前目录
- `g a` 选 agent
- PDF：右栏即预览；`J`/`K` 翻页；`I` Quick Look；`Enter` 才是 Acrobat

## 不改的

- 不装 flavor、不再 `ya pkg` 装插件。
- 不改 `l` = smart-enter、`S` = shell、`z`/`Z`、tab 数字键。
- 不把 Cursor 的 `agent` 放进菜单。

## 怎么验证

改完后在 Ghostty 里开一次 yazi（配置是启动时读的，已开着的要重开）：

1. 普通文件、目录、选中行、状态栏能分开，没有一块发白的字压在发白的底上。
2. `~` 能打开按键列表，`f` 输入 `extract` / `agent` 能滤到新条目。
3. 两个目录：`Space` 选几个文件，`y`，`g d` 或手动进入另一目录，`p`，再 `H` 回到原目录，文件还在、目标目录有副本。
4. 对一个 zip：`e`，文件出现在当前目录，不用先 `Enter`。
5. `g a` 弹出 5 个名字，选 pi 能在该目录起进程，退出后仍在 yazi。
6. 悬停一个 PDF：右栏出页面图，不是 Acrobat。`J`/`K` 换页。只有 `Enter` 才交给系统默认应用。
