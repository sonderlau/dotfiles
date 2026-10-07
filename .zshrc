# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
export ZSH_WAKATIME_PROJECT_DETECTION=true

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_DISABLE_COMPFIX=true

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# ZSH_THEME="powerlevel10k/powerlevel10k"
# ZSH_THEME="robbyrussell"
eval "$(starship init zsh)"

# No beep sound
unsetopt beep

# Sparkling cursor
printf '\e[1 q'

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git
  python
  uv
  tt
  brew
  rsync
  fzf)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"


source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

alias cat="bat"
alias ls="eza --icons"
alias lsl="eza --icons -l"
alias lzg="lazygit"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
alias airport="/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport"
export PATH=$PATH:/Users/sonderlau/.spicetify

export PATH="/Users/sonderlau/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"

[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

[ ! -f "$HOME/.x-cmd.root/X" ] || . "$HOME/.x-cmd.root/X" # boot up x-cmd.

alias proxy="
    export http_proxy=socks5h://127.0.0.1:7890;
    export https_proxy=socks5h://127.0.0.1:7890;
    export all_proxy=socks5h://127.0.0.1:7890;
    export no_proxy=localhost,127.0.0.1,::1,.local;
    export HTTP_PROXY=socks5h://127.0.0.1:7890;
    export HTTPS_PROXY=socks5h://127.0.0.1:7890;
    export ALL_PROXY=socks5h://127.0.0.1:7890;
    export NO_PROXY=localhost,127.0.0.1,::1,.local;"
alias unproxy="
    unset http_proxy;
    unset https_proxy;
    unset all_proxy;
    unset no_proxy;
    unset HTTP_PROXY;
    unset HTTPS_PROXY;
    unset ALL_PROXY;
    unset NO_PROXY"

alias yz=yazi
alias v=nvim
alias j=z
alias finder=open .


[ -f ~/.secrets ] && source ~/.secrets
export PATH=$PATH:$HOME/go/bin
export GPG_TTY=$(tty)

export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_BOTTLE_DOMAIN="https://mirror.nju.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirror.nju.edu.cn/homebrew-bottles/api"
export HOMEBREW_BREW_GIT_REMOTE="https://mirror.nju.edu.cn/git/homebrew/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirror.nju.edu.cn/git/homebrew/homebrew-core.git"
export HOMEBREW_INSTALL_FROM_API=1

export XDG_CONFIG_HOME="$HOME/.config"


export UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

eval "$(zoxide init zsh)"

# Yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
[ -s "/Users/sonderlau/.bun/_bun" ] && source "/Users/sonderlau/.bun/_bun"

# Claude Memory
alias claude-mem='bun "/Users/sonderlau/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'

# Opencode

alias oc='opencode'
alias occ='opencode -c'

# Claude
alias cc='claude --dangerously-skip-permissions'
alias ccr='claude --dangerously-skip-permissions --resume'


# ==========================================
# uv 智能环境调度 (支持全局 base 兜底与子目录继承)
# ==========================================
export UV_BASE_ENV="$HOME/.uv-base/.venv"
autoload -U add-zsh-hook

_auto_activate_venv() {
    local target_env=""
    local check_dir="$PWD"

    # 1. 向上递归查找最近的项目的 .venv
    while [[ "$check_dir" != "/" && "$check_dir" != "$HOME" ]]; do
        if [[ -f "$check_dir/.venv/bin/activate" ]]; then
            target_env="$check_dir/.venv"
            break
        fi
        check_dir="$(dirname "$check_dir")"
    done

    # 2. 如果没找到项目专有的环境，就退回兜底的 base 环境
    if [[ -z "$target_env" ]]; then
        target_env="$UV_BASE_ENV"
    fi

    # 3. 如果需要切换，则正式 source 激活它
    if [[ -f "$target_env/bin/activate" && "$VIRTUAL_ENV" != "$target_env" ]]; then
        source "$target_env/bin/activate"
    fi
}

add-zsh-hook chpwd _auto_activate_venv
_auto_activate_venv

# ──────────────── tmux integration ────────────────
# 工作流和命名规则继承自之前的 zellij 时期。
# zd/za/zk 命令保留，底层切换到 tmux。

# 前缀匹配解析器：根据前缀找唯一 session
# 0 匹配 → echo 空 + 返回 1
# 1 匹配 → echo 该名字 + 返回 0
# 多匹配 → 列到 stderr + 返回 2
__tmux_resolve() {
    local prefix="$1"
    local raw
    raw=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^$prefix")
    if [[ -z "$raw" ]]; then
        print -u2 "no session matches '$prefix'"
        return 1
    fi
    local matches
    matches=("${(@f)raw}")
    case ${#matches[@]} in
        1) print -- "$matches[1]"; return 0 ;;
        *) print -u2 "ambiguous '$prefix' matches:"
           printf '  %s\n' "${matches[@]}" >&2
           return 2 ;;
    esac
}

# zd: 进入项目 session（命名规则：<父目录>-<当前目录>）
# - 不带参 → 用当前目录命名规则 attach（不存在则创建）
# - 带参   → 前缀匹配现有 session
unalias zd za zk 2>/dev/null
zd() {
    local name
    if [[ -n "$1" ]]; then
        name=$(__tmux_resolve "$1") || return $?
        tmux attach-session -t "$name"
    else
        name="$(basename "$(dirname "$PWD")")-$(basename "$PWD")"
        # tmux 的 session 名不能含 . 等特殊字符，替换为 -
        name="${name//./-}"
        tmux new-session -A -s "$name" -c "$PWD"
    fi
}

# za: attach 到任意现有 session（前缀匹配）
za() {
    [[ -z "$1" ]] && { print -u2 "usage: za <prefix>"; return 1; }
    local name
    name=$(__tmux_resolve "$1") || return $?
    tmux attach-session -t "$name"
}

# zk: kill session（前缀匹配）
zk() {
    [[ -z "$1" ]] && { print -u2 "usage: zk <prefix>"; return 1; }
    local name
    name=$(__tmux_resolve "$1") || return $?
    tmux kill-session -t "$name"
}

alias zl='tmux list-sessions'

# >>> oh-my-opencode-slim background subagents >>>
export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
# <<< oh-my-opencode-slim background subagents <<<
#
#
#
njulogin() {
    curl -d '{"username":"602023280010","password":"Ylmdlm@720","domain":"default"}' https://p.nju.edu.cn/api/portal/v1/login
}
