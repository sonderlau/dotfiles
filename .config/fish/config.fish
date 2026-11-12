# PATH runs for interactive and non-interactive sessions (scripts, editors, Grok).
# macOS /etc/paths puts /usr/local/bin first (stale Node 18 pkg). Homebrew must
# beat that; bun/cargo/local stay ahead of Homebrew.
# conf.d/homebrew.fish already runs brew shellenv; --move here reasserts order.
fish_add_path --global --move --path \
    $HOME/.bun/bin \
    $HOME/.local/bin \
    $HOME/.cargo/bin \
    $HOME/go/bin \
    $HOME/.grok/bin \
    $HOME/.spicetify \
    /opt/homebrew/opt/llvm/bin \
    /opt/homebrew/bin \
    /opt/homebrew/sbin

if not status is-interactive
    return
end

set -g fish_greeting ''

# --------------------------------------------------
# Environment
# --------------------------------------------------
set -gx GPG_TTY (tty)
set -gx EDITOR nvim
set -gx HOMEBREW_NO_ENV_HINTS 1
set -gx HOMEBREW_NO_AUTO_UPDATE 1
set -gx HOMEBREW_NO_ANALYTICS 1
set -gx HOMEBREW_BOTTLE_DOMAIN https://mirror.nju.edu.cn/homebrew-bottles
set -gx HOMEBREW_API_DOMAIN https://mirror.nju.edu.cn/homebrew-bottles/api
set -gx HOMEBREW_BREW_GIT_REMOTE https://mirror.nju.edu.cn/git/homebrew/brew.git
set -gx HOMEBREW_CORE_GIT_REMOTE https://mirror.nju.edu.cn/git/homebrew/homebrew-core.git
set -gx HOMEBREW_INSTALL_FROM_API 1
set -gx XDG_CONFIG_HOME $HOME/.config
set -gx UV_INDEX_URL https://pypi.tuna.tsinghua.edu.cn/simple
set -gx BUN_INSTALL $HOME/.bun
set -gx UV_BASE_ENV $HOME/.uv-base/.venv
set -gx ZSH_WAKATIME_PROJECT_DETECTION true
set -gx CLAUDE_CODE_NO_FLICKER 1
set -gx OMO_SEND_ANONYMOUS_TELEMETRY 0

if not set -q HOMEBREW_MAKE_JOBS
    set -l logical_cpu (sysctl -n hw.logicalcpu 2>/dev/null)
    if test -n "$logical_cpu"
        set -gx HOMEBREW_MAKE_JOBS $logical_cpu
    end
end

set -gx FZF_DEFAULT_OPTS '--height 75% --layout=reverse --border --info=inline'

# --------------------------------------------------
# Shell integrations
# --------------------------------------------------
printf '\e[1 q'

if command -q starship
    starship init fish | source
end

if command -q zoxide
    zoxide init fish | source
end

if command -q fzf
    fzf --fish | source
end

if test "$TERM_PROGRAM" = kiro; and command -q kiro
    source (kiro --locate-shell-integration-path fish)
end

# Fish loads ~/.config/fish/conf.d/*.fish before this file.
if test -f $HOME/.orbstack/shell/init2.fish
    source $HOME/.orbstack/shell/init2.fish
end

# x-cmd's zsh bootstrap is not fish-compatible. Enable this after confirming
# `xrc fish` works in your environment.
# bash -lc 'source "$HOME/.x-cmd.root/X" >/dev/null 2>&1; xrc fish 2>/dev/null' | source

# Bun's existing ~/.bun/_bun file is zsh completion and must not be sourced by
# fish. Bun itself works through PATH; completion can be added separately later.

# --------------------------------------------------
# Aliases
# --------------------------------------------------
alias cat='bat'
alias ls='eza --icons'
alias lsl='eza --icons -l'
alias lzg='lazygit'
alias airport='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport'
alias yz='yazi'
alias v='nvim'
alias j='z'
alias finder='open .'
alias claude-mem='bun "$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'
alias oc='opencode'
alias occ='opencode -c'
alias cc='claude --dangerously-skip-permissions'
alias ccr='claude --dangerously-skip-permissions --resume'
alias zl='tmux list-sessions'

# --------------------------------------------------
# Abbreviations
# --------------------------------------------------
abbr -a c clear
abbr -a reload 'exec fish'
abbr -a batcat bat
abbr -a e eza
abbr -a el 'eza --icons -l'
abbr -a ea 'eza --icons -la'
abbr -a et 'eza --icons --tree --level=2'
abbr -a lg lazygit
abbr -a yazi yazi
abbr -a nv nvim
abbr -a op opencode
abbr -a opc 'opencode -c'
abbr -a claude-mem 'bun "$HOME/.claude/plugins/marketplaces/thedotmack/plugin/scripts/worker-service.cjs"'
abbr -a ccr 'claude --dangerously-skip-permissions --resume'
abbr -a proxy-on proxy
abbr -a proxy-off unproxy
abbr -a finder 'open .'
abbr -a py python
abbr -a uvr 'uv run'
abbr -a uvs 'uv sync'
abbr -a bi 'brew install'
abbr -a br 'brew reinstall'
abbr -a bui 'brew uninstall'
abbr -a bs 'brew search'
abbr -a bif 'brew info'
abbr -a bl 'brew leaves; and brew list --cask'
abbr -a bu 'brew update; and brew upgrade'
abbr -a bc 'brew autoremove; and brew cleanup --prune=all'
abbr -a tls 'tmux list-sessions'
abbr -a tn 'tmux new-session -s'
abbr -a ta 'tmux attach-session -t'
abbr -a tk 'tmux kill-session -t'
abbr -a zd zd
abbr -a za za
abbr -a zk zk

# --------------------------------------------------
# Proxy helpers
# --------------------------------------------------
function proxy
    set -gx http_proxy socks5h://127.0.0.1:7890
    set -gx https_proxy socks5h://127.0.0.1:7890
    set -gx all_proxy socks5h://127.0.0.1:7890
    set -gx no_proxy localhost,127.0.0.1,::1,.local
    set -gx HTTP_PROXY socks5h://127.0.0.1:7890
    set -gx HTTPS_PROXY socks5h://127.0.0.1:7890
    set -gx ALL_PROXY socks5h://127.0.0.1:7890
    set -gx NO_PROXY localhost,127.0.0.1,::1,.local
end

function unproxy
    set -e http_proxy https_proxy all_proxy no_proxy
    set -e HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
end

# --------------------------------------------------
# Timestamp helper, migrated from oh-my-zsh plugin `tt`
# --------------------------------------------------
function tt
    if not set -q argv[1]
        date +%s
    else if string match -q '*-*' -- $argv[1]
        if string match -q '* *' -- $argv[1]
            date -j -f '%Y-%m-%d %H:%M:%S' $argv[1] +%s 2>/dev/null
        else
            date -j -f '%Y-%m-%d %H:%M:%S' "$argv[1] 00:00:00" +%s 2>/dev/null
        end
    else
        date -r $argv[1] '+%Y-%m-%d %H:%M:%S'
    end
end

# --------------------------------------------------
# Yazi cwd wrapper
# --------------------------------------------------
function y
    set -l tmp (mktemp -t 'yazi-cwd.XXXXXX')
    command yazi $argv --cwd-file=$tmp

    set -l cwd
    read -z cwd <$tmp

    if test -n "$cwd"; and test "$cwd" != "$PWD"; and test -d "$cwd"
        cd "$cwd"
    end

    command rm -f -- $tmp
end

# --------------------------------------------------
# uv venv auto activation
# --------------------------------------------------
function _auto_activate_venv --on-variable PWD
    set -l target_env
    set -l check_dir $PWD

    while test "$check_dir" != /; and test "$check_dir" != $HOME
        if test -f "$check_dir/.venv/bin/activate.fish"
            set target_env "$check_dir/.venv"
            break
        end

        set check_dir (dirname "$check_dir")
    end

    if test -z "$target_env"
        set target_env $UV_BASE_ENV
    end

    if test -f "$target_env/bin/activate.fish"; and test "$VIRTUAL_ENV" != "$target_env"
        source "$target_env/bin/activate.fish"
    end
end

_auto_activate_venv

# --------------------------------------------------
# tmux helpers
# --------------------------------------------------
function __tmux_resolve
    if not set -q argv[1]
        echo 'usage: __tmux_resolve <prefix>' >&2
        return 1
    end

    set -l prefix $argv[1]
    set -l matches (tmux list-sessions -F '#{session_name}' 2>/dev/null | string match "$prefix*")

    switch (count $matches)
        case 0
            echo "no session matches '$prefix'" >&2
            return 1
        case 1
            echo $matches[1]
            return 0
        case '*'
            echo "ambiguous '$prefix' matches:" >&2
            printf '  %s\n' $matches >&2
            return 2
    end
end

function zd
    set -l name

    if set -q argv[1]
        set name (__tmux_resolve $argv[1]); or return $status
        tmux attach-session -t "$name"
    else
        set name (basename (dirname "$PWD"))-(basename "$PWD")
        set name (string replace -a . - "$name")
        tmux new-session -A -s "$name" -c "$PWD"
    end
end

function za
    if not set -q argv[1]
        echo 'usage: za <prefix>' >&2
        return 1
    end

    set -l name (__tmux_resolve $argv[1]); or return $status
    tmux attach-session -t "$name"
end

function zk
    if not set -q argv[1]
        echo 'usage: zk <prefix>' >&2
        return 1
    end

    set -l name (__tmux_resolve $argv[1]); or return $status
    tmux kill-session -t "$name"
end

# >>> grok installer >>>
fish_add_path $HOME/.grok/bin
# <<< grok installer <<<
# >>> grok doctor >>>
# >>> terminal.ssh-wrap >>>
alias ssh 'grok wrap ssh'
# <<< terminal.ssh-wrap <<<
# <<< grok doctor <<<


# Added by Antigravity CLI installer
set -gx PATH "/Users/sonderlau/.local/bin" $PATH
