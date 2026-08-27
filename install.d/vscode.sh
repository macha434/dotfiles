#!/usr/bin/env bash
# VS Code のユーザー設定を配置する。
#
# 設置先 (VS Code の既定):
#   linux   ${XDG_CONFIG_HOME:-~/.config}/Code/User/
#   macos   ~/Library/Application Support/Code/User/
#   windows %APPDATA%/Code/User/
#   wsl     Windows 側の %APPDATA%/Code/User/
#           (WSL から使う VS Code は Windows 側のクライアントなので、
#            設定を読むのも Windows 側のパス。~/.config/Code は VS Code を
#            入れていなくても残っていることがあるので、存在するかでは
#            判定しない。Linux 版にも置きたい場合は
#            DOTFILES_VSCODE_LINUX=1 を付けて実行する)

vscode_user_dirs() {
    case "$DOTFILES_OS" in
        macos)
            printf '%s\n' "$HOME/Library/Application Support/Code/User"
            ;;
        linux)
            printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
            ;;
        windows)
            printf '%s\n' "$(windows_appdata)/Code/User"
            ;;
        wsl)
            printf '%s\n' "$(windows_appdata)/Code/User"
            if [ "${DOTFILES_VSCODE_LINUX:-0}" = 1 ]; then
                printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User"
            fi
            ;;
    esac
}

while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    install_file "$DOTFILES_ROOT/vscode/settings.json"    "$dir/settings.json"
    install_file "$DOTFILES_ROOT/vscode/keybindings.json" "$dir/keybindings.json"
done < <(vscode_user_dirs)
