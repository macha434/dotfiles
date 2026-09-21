#!/usr/bin/env bash
# VS Code のユーザー設定を配置する。設置先は README.ja.md の「配置先」表を参照。

# CHEATSHEET.md を開くキーバインドが使う file:// URI を組み立てる。
# キーバインドを実際に処理するプロセス (WSL なら既定では Remote-WSL の
# クライアントである Windows 側の VS Code) が解釈できるパス形式にする必要が
# あるため、target_is_windows で判定して OS ごとのパス変換を挟む。
cheatsheet_file_uri() {
    local path=$1 winpath
    if target_is_windows "$path"; then
        case "$DOTFILES_OS" in
            windows) winpath=$(cygpath -w "$path") || die "cygpath に失敗: $path" ;;
            wsl)     winpath=$(wslpath -w "$path") || die "wslpath に失敗: $path" ;;
        esac
        printf 'file:///%s\n' "${winpath//\\//}"
    else
        printf 'file://%s\n' "${path// /%20}"
    fi
}

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
    install_file "$DOTFILES_ROOT/vscode/CHEATSHEET.md"    "$dir/CHEATSHEET.md"

    if [ "${DRY_RUN:-0}" != 1 ]; then
        uri=$(cheatsheet_file_uri "$dir/CHEATSHEET.md")
        tmp="$dir/keybindings.json.tmp"
        sed "s|__DOTFILES_CHEATSHEET_URI__|$uri|" "$dir/keybindings.json" > "$tmp" \
            && mv "$tmp" "$dir/keybindings.json"
    fi
done < <(vscode_user_dirs)
