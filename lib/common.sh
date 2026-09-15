#!/usr/bin/env bash
# install.sh と install.d/*.sh が共有するヘルパ。
# 単体では実行せず、source して使う。

# ---- 出力 ---------------------------------------------------------------
if [ -t 1 ]; then
    _c_reset=$'\033[0m'; _c_dim=$'\033[2m'; _c_red=$'\033[31m'
    _c_green=$'\033[32m'; _c_yellow=$'\033[33m'; _c_blue=$'\033[34m'
else
    _c_reset=; _c_dim=; _c_red=; _c_green=; _c_yellow=; _c_blue=
fi

info() { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$_c_blue" "$_c_reset" "$*"; }
ok()   { printf '  %sok%s   %s\n' "$_c_green" "$_c_reset" "$*"; }
skip() { printf '  %sskip%s %s\n' "$_c_dim" "$_c_reset" "$*"; }
warn() { printf '  %swarn%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$_c_red" "$_c_reset" "$*" >&2; exit 1; }

# ---- OS 判定 ------------------------------------------------------------
detect_os() {
    if [ -n "${DOTFILES_OS:-}" ]; then
        return
    fi
    case "$(uname -s)" in
        Darwin)             DOTFILES_OS=macos ;;
        MINGW*|MSYS*|CYGWIN*) DOTFILES_OS=windows ;;
        Linux)
            # WSL は /proc/version に microsoft が入る
            if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                DOTFILES_OS=wsl
            else
                DOTFILES_OS=linux
            fi
            ;;
        *) die "判別できない OS: $(uname -s)" ;;
    esac
    export DOTFILES_OS
}

# 設置先が Windows のファイルシステムかどうかを、パスごとに判断する。
target_is_windows() {
    local dest=$1
    case "$DOTFILES_OS" in
        windows) return 0 ;;
        wsl)
            case "$dest" in
                /mnt/*) return 0 ;;
                *)      return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

# ---- Windows のパス -----------------------------------------------------
# %APPDATA% を unix 形式のパスで返す (wsl / windows のみ)。
_win_appdata_cache=
windows_appdata() {
    if [ -n "$_win_appdata_cache" ]; then
        printf '%s\n' "$_win_appdata_cache"
        return
    fi
    local raw path
    case "$DOTFILES_OS" in
        windows)
            path=$(cygpath -u "$APPDATA" 2>/dev/null) || path=
            ;;
        wsl)
            # cmd.exe は cwd が UNC パスだと警告を出すので /mnt/c から呼ぶ
            raw=$(cd /mnt/c 2>/dev/null && cmd.exe /c 'echo %APPDATA%' 2>/dev/null | tr -d '\r\n') || raw=
            if [ -n "$raw" ]; then
                path=$(wslpath -u "$raw" 2>/dev/null) || path=
            fi
            # cmd.exe が使えない環境向けのフォールバック
            if [ -z "$path" ] && [ -d "/mnt/c/Users/$USER/AppData/Roaming" ]; then
                path="/mnt/c/Users/$USER/AppData/Roaming"
            fi
            ;;
        *)
            die "windows_appdata は $DOTFILES_OS では使えない"
            ;;
    esac
    [ -n "$path" ] || die "%APPDATA% を特定できなかった。DOTFILES_WIN_APPDATA で明示してほしい"
    _win_appdata_cache=$path
    printf '%s\n' "$path"
}
if [ -n "${DOTFILES_WIN_APPDATA:-}" ]; then
    _win_appdata_cache=$DOTFILES_WIN_APPDATA
fi

# ---- 設置 ---------------------------------------------------------------
# install_file <src> <dest> : 常にコピーで配置する (symlink は張らない)。
install_file() {
    local src=$1 dest=$2
    [ -f "$src" ] || die "元ファイルが無い: $src"

    local dest_dir
    dest_dir=$(dirname "$dest")

    if [ "${DRY_RUN:-0}" = 1 ]; then
        skip "(dry-run) copy   $dest"
        return
    fi

    mkdir -p "$dest_dir" || die "作成できない: $dest_dir"

    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        if target_is_windows "$dest"; then
            if diff -q --strip-trailing-cr "$src" "$dest" >/dev/null 2>&1; then
                skip "同一 $dest"
                return
            fi
        else
            if diff -q "$src" "$dest" >/dev/null 2>&1; then
                skip "同一 $dest"
                return
            fi
        fi
    fi

    _backup "$dest"
    # 旧バージョンが symlink を張っていた名残がある場合、そのまま cp すると
    # リンク先 (= src 自身) に書き込んでしまうので、先に外しておく。
    [ -L "$dest" ] && rm -f "$dest"
    cp "$src" "$dest" || die "コピーできない: $dest"
    ok "copy $dest"
}

# 設置前の状態を 1 度だけ退避する。symlink (旧バージョンの名残) は退避不要。
_backup() {
    local dest=$1
    local backup="$dest.dotfiles.bak"
    if [ -e "$dest" ] && [ ! -L "$dest" ] && [ ! -e "$backup" ]; then
        cp "$dest" "$backup" || die "退避できない: $dest"
        warn "退避 $backup"
    fi
}
