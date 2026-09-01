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

    # インストーラは最後に「Start Codex now? [y/N]」と訊く。postCreate に答える
    # 相手は居ないので、既定の N が黙って選ばれるように三重に手を打つ。
    #
    #   1. curl | sh をやめてファイルに落とす。パイプのままだとインストーラの
    #      read が「まだ実行していないスクリプト自身の続き」を食ってしまう。
    #   2. stdin を /dev/null にする。stdin から読む実装ならこれで EOF になる。
    #   3. setsid -w で制御端末を切り離す。/dev/tty を直接開く実装には 2 が
    #      効かないのでこれが要る。-w が無いと子を待たず終了ステータスも
    #      拾えないので必ず付ける。setsid が無い環境では 1 と 2 だけで進める。
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

# インストーラが張るランチャは ~/.local/bin、つまりイメージ側にある。
# コンテナを作り直すと消えるので、volume に実体があるなら張り直す。
if [ -x "$pkg" ]; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$pkg" "$HOME/.local/bin/codex"
fi
