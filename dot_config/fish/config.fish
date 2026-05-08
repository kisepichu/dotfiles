function __is_wsl
    string match -qi "*microsoft*" (uname -r)
end

function __path_prepend
    for dir in $argv
        if test -d "$dir"; and not contains -- "$dir" $PATH
            set -gx PATH "$dir" $PATH
        end
    end
end

set -gx REPOS "$HOME/repos"
set -gx TRASH "$HOME/_trash"
set -gx SAVE "$HOME/_save"

__path_prepend "$HOME/.local/bin"
__path_prepend "$HOME/.cargo/bin"
__path_prepend "$HOME/.elan/bin"
__path_prepend "$HOME/gems/bin"
__path_prepend "$HOME/.local/share/pnpm"

if test -n "$PNPM_HOME"
    __path_prepend "$PNPM_HOME"
else if test -d "$HOME/.local/share/pnpm"
    set -gx PNPM_HOME "$HOME/.local/share/pnpm"
end

if test -d "$HOME/.dotnet"
    set -gx DOTNET_ROOT "$HOME/.dotnet"
    __path_prepend "$DOTNET_ROOT" "$DOTNET_ROOT/tools"
end

if __is_wsl
    set -gx WREPOS /mnt/c/repos

    if command -q wslvar; and command -q wslpath
        set -l windows_home (wslpath (wslvar USERPROFILE 2>/dev/null) 2>/dev/null)
        if test -n "$windows_home"; and test -d "$windows_home"
            set -gx WHOME "$windows_home"
            set -gx DOWNLOAD "$windows_home/Downloads"
        end
    end

    __path_prepend /mnt/c/Windows /mnt/c/Windows/system32

    if command -q wslview
        set -gx BROWSER wslview
    end

    if test -d /mnt/c/Windows/Fonts
        set -gx TYPST_FONT_PATHS "/mnt/c/fonts:/mnt/c/Windows/Fonts"
    end
end

set -l current_tty (tty 2>/dev/null)
if test $status -eq 0
    set -gx GPG_TTY "$current_tty"
end

if test -d "$HOME/gems"
    set -gx GEM_HOME "$HOME/gems"
end

if command -q mise
    mise activate fish | source
end

if not set -q STARSHIP_CONFIG; and test -f "$HOME/.config/starship.toml"
    set -gx STARSHIP_CONFIG "$HOME/.config/starship.toml"
end

if status is-interactive
    alias reb="exec fish -l"
    alias python=python3
    alias pip=pip3
    alias ll="ls -alF"
    alias la="ls -A"
    alias l="ls -CF"
    alias mtu="sudo ip link set eth0 mtu 1404"

    if command -q pnpm
        alias npm=pnpm
    end

    if __is_wsl
        alias clip="clip.exe"

        if command -q powershell.exe; and test -f /bin/paste.ps1
            alias paste="powershell.exe /bin/paste.ps1"
        end
    end

    if command -q gh
        gh completion -s fish | source
    end

    if test "$SHLVL" = 1
        alias tm="tmux -2 attach || tmux -2 new-session \\; source-file ~/.tmux/new-session"
    end

    alias tmux-reset-layout="tmux select-layout \"\$(tmux show-options -gv @layout_pc)\""
end

function __unique_destination
    set -l directory "$argv[1]"
    set -l name "$argv[2]"
    set -l destination "$directory/$name"
    if not test -e "$destination"
        echo "$destination"
        return 0
    end

    set -l stamp (date +%Y%m%d%H%M%S)
    set -l index 1
    while test -e "$directory/$name.$stamp.$index"
        set index (math $index + 1)
    end
    echo "$directory/$name.$stamp.$index"
end

function del
    if test (count $argv) -eq 0
        return 1
    end
    mkdir -p "$TRASH"
    for target in $argv
        set -l destination (__unique_destination "$TRASH" (basename "$target"))
        command mv -- "$target" "$destination"
    end
end

function save
    if test (count $argv) -eq 0
        return 1
    end
    mkdir -p "$SAVE"
    for target in $argv
        set -l destination (__unique_destination "$SAVE" (basename "$target"))
        command cp -R -- "$target" "$destination"
    end
end

function browse
    if test (count $argv) -eq 0
        return 1
    end

    set -l target (realpath "$argv[1]")
    if __is_wsl; and set -q BROWSER
        "$BROWSER" "$target"
    else if set -q BROWSER
        "$BROWSER" "$target"
    else
        xdg-open "$target"
    end
end

if command -q starship
    starship init fish | source
end

if command -q zoxide
    zoxide init fish | source
end

if set -q TERM_PROGRAM; and string match -q "$TERM_PROGRAM" vscode; and command -q code
    set -l integration_path (code --locate-shell-integration-path fish 2>/dev/null)
    if test -n "$integration_path"; and test -f "$integration_path"
        source "$integration_path"
    end
end
