#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る。
#
# Codex のインストーラはバイナリ本体を ~/.codex/packages/ に置く。そこは volume の
# 中なので、ビルド時に入れてもコピーアップが起きる初回にしか届かない。かといって
# entrypoint でやるとネットワーク越しのダウンロードがコンテナ起動をブロックする。
# postCreate なら remote user で走り、devcontainer が完了を待ってくれる。
set -eu

. /usr/local/share/macha-features/config

[ "${CODEX:-false}" = "true" ] || exit 0

pkg="$STATE/codex/packages/standalone/current/bin/codex"

if [ ! -x "$pkg" ]; then
    echo "macha-features: Codex CLI が volume に無いので入れる"
    if ! curl -fsSL https://chatgpt.com/codex/install.sh | sh; then
        echo "macha-features: Codex CLI のインストールに失敗した" >&2
        exit 0
    fi
fi

# インストーラが張るランチャは ~/.local/bin、つまりイメージ側にある。
# コンテナを作り直すと消えるので、volume に実体があるなら張り直す。
if [ -x "$pkg" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$pkg" "$HOME/.local/bin/codex"
fi
