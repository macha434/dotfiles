#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る。
# Codex のバイナリは volume の中に入るため、entrypoint ではなくここで扱う。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

[ "${CODEX:-false}" = "true" ] || exit 0

# config.toml は無いときだけ置く (install.sh は volume 未マウントで判定できないため。README 参照)
cfg="$STATE/codex/config.toml"
if [ ! -e "$cfg" ] && [ -f "$SHARE/codex-config.toml" ]; then
    echo "macha-features: codex/config.toml が volume に無いので置く"
    install -m 644 "$SHARE/codex-config.toml" "$cfg"
fi

pkg="$STATE/codex/packages/standalone/current/bin/codex"

if [ ! -x "$pkg" ]; then
    echo "macha-features: Codex CLI が volume に無いので入れる"

    # 対話プロンプトの既定 N を黙って選ばせるため、ファイル実行 + stdin /dev/null + setsid -w の三重構え
    installer=$(mktemp)
    ok=0
    if curl -fsSL https://chatgpt.com/codex/install.sh -o "$installer"; then
        if command -v setsid >/dev/null 2>&1; then
            if setsid -w sh "$installer" </dev/null; then ok=1; fi
        else
            if sh "$installer" </dev/null; then ok=1; fi
        fi
    fi
    rm -f "$installer"

    if [ "$ok" != 1 ]; then
        echo "macha-features: Codex CLI のインストールに失敗した" >&2
        exit 0
    fi
fi

# ランチャ (~/.local/bin/codex) はイメージ側なのでコンテナ作り直しで消える。毎回張り直す
if [ -x "$pkg" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$pkg" "$HOME/.local/bin/codex"
fi
