#!/usr/bin/env bash
# コンテナ起動ごとに root で走る。volume はマウント済み。
#
# ビルド時に決まる値 (remote user 名や option) はここからは見えないので、
# install.sh が config に焼き込んだものを読む。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

uid=$(id -u "$USERNAME")
gid=$(id -g "$USERNAME")

# 既に中身のある volume を掴んだ場合、コピーアップは起きない。
for name in "${AGENTS[@]}"; do
    [ -d "$STATE/$name" ] || mkdir -p "$STATE/$name"
done

# 別 uid のイメージが初期化した volume と、直前の行が root で作ったばかりの
# サブディレクトリの両方に備える。$STATE だけを見ると後者を取りこぼす。
# bind mount と違いホスト側に実体が無いので chown して差し支えない。
if [ "$(id -u)" = 0 ]; then
    for dir in "$STATE" "${AGENTS[@]/#/$STATE/}"; do
        [ -d "$dir" ] || continue
        [ "$(stat -c %u "$dir")" = "$uid" ] || chown -R "$uid:$gid" "$dir"
        chmod 700 "$dir"
    done
fi

# settings.json は volume の中にあり、コピーアップは初回しか起きない。
# ビルド時に書くと 2 回目以降のコンテナに届かないので、毎起動ここで当てる。
# スクリプト本体はイメージ側 ($SHARE) にあるのでパスは不変。
apply_claude_statusline() {
    local settings="$STATE/claude/settings.json"
    local script="$SHARE/claude-statusline.sh"
    [ -x "$script" ] || return 0

    if ! command -v jq >/dev/null 2>&1; then
        # jq が無い環境では既存を壊さないよう、無いときだけ作る
        [ -e "$settings" ] && return 0
        printf '{"statusLine":{"type":"command","command":"%s"}}\n' "$script" > "$settings"
    else
        [ -s "$settings" ] || echo '{}' > "$settings"
        local tmp
        tmp=$(mktemp)
        if jq --arg cmd "$script" \
             '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$settings"
        else
            rm -f "$tmp"
            echo "macha-features: $settings が JSON として読めないので statusLine は当てない" >&2
            return 0
        fi
    fi
    chown "$uid:$gid" "$settings"
    chmod 600 "$settings"
}

if [ "${CLAUDE:-false}" = "true" ]; then
    apply_claude_statusline
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
