#!/usr/bin/env bash
# VS Code のユーザー設定を配置する。設置先は README.ja.md の「配置先」表を参照。

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
