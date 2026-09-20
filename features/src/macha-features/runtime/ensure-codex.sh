#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る。
set -eu

# shellcheck source=/dev/null
. /usr/local/share/macha-features/lib/common.sh
# shellcheck source=/dev/null
. "$SHARE/config"

[ "${CODEX:-false}" = "true" ] || exit 0

# config.toml が volume に無いときだけ置く
place_config_if_missing() {
    local cfg="$STATE/codex/config.toml"
    [ -e "$cfg" ] && return 0
    [ -f "$SHARE/codex-config.toml" ] || return 0

    echo "macha-features: codex/config.toml が volume に無いので置く"
    install -m 644 "$SHARE/codex-config.toml" "$cfg"
}

# Codex バイナリが volume に無ければインストーラを実行する
install_codex_binary() {
    local pkg="$STATE/codex/packages/standalone/current/bin/codex"
    [ -x "$pkg" ] && return 0

    echo "macha-features: Codex CLI が volume に無いので入れる"

    local installer ok=0
    installer=$(mktemp)
    # --retry: 5xx やタイムアウトの一時的な失敗 (実機で 504 を確認済み) を自動で拾い直す
    if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
            https://chatgpt.com/codex/install.sh -o "$installer"; then
        if command -v setsid >/dev/null 2>&1; then
            setsid -w sh "$installer" </dev/null && ok=1
        else
            sh "$installer" </dev/null && ok=1
        fi
    fi
    rm -f "$installer"

    [ "$ok" = 1 ] || echo "macha-features: Codex CLI のインストールに失敗した" >&2
}

# ~/.local/bin/codex をバイナリの実体へ毎回張り直す
link_launcher() {
    local pkg="$STATE/codex/packages/standalone/current/bin/codex"
    [ -x "$pkg" ] || return 0

    mkdir -p "$HOME/.local/bin"
    ln -sfn "$pkg" "$HOME/.local/bin/codex"
}

place_config_if_missing
install_codex_binary
link_launcher
