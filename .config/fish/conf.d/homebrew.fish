# Ghostty (and other GUI apps) start fish with a minimal PATH.
# zsh gets brew via ~/.zprofile; fish needs this or starship/eza/fzf disappear.
# This moves /opt/homebrew/bin ahead of /usr/local/bin from /etc/paths.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
end
