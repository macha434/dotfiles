#!/usr/bin/env bash
# コンテナ起動ごとに root で走る。volume はマウント済み。
# ビルド時の値 (remote user 名や option) は install.sh が焼き込んだ config から読む。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

uid=$(id -u "$USERNAME")
gid=$(id -g "$USERNAME")

# 既に中身のある volume を掴んだ場合、コピーアップは起きない
for name in "${AGENTS[@]}"; do
    [ -d "$STATE/$name" ] || mkdir -p "$STATE/$name"
done

# $STATE 直下だけでなく各 $STATE/$name も見る (直前で新規作成した分を取りこぼさないため)
if [ "$(id -u)" = 0 ]; then
    for dir in "$STATE" "${AGENTS[@]/#/$STATE/}"; do
        [ -d "$dir" ] || continue
        [ "$(stat -c %u "$dir")" = "$uid" ] || chown -R "$uid:$gid" "$dir"
        chmod 700 "$dir"
    done
fi

# claude/settings.json と copilot/settings.json は volume の中にあるので毎起動ここで当てる
#
#   $1 volume 側の設定ファイル
#   $2 $SHARE のテンプレート
#   $3 $SHARE の statusline スクリプト
#   $4 refreshInterval の秒数 (空なら付けない)
apply_json_config() {
    local dest=$1 template=$2 script=$3 refresh=$4
    [ -f "$template" ] || return 0
    [ -x "$script" ] || return 0

    # refreshInterval はレート制限表示の更新に要る (無い側では付けない)
    local sl
    if [ -n "$refresh" ]; then
        sl=$(printf '{"type":"command","command":"%s","refreshInterval":%s}' "$script" "$refresh")
    else
        sl=$(printf '{"type":"command","command":"%s"}' "$script")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        # jq が無い環境では既存を壊さないよう、ファイルが無いときだけ最小構成を書く
        if [ ! -e "$dest" ]; then
            printf '{"statusLine":%s}\n' "$sl" > "$dest"
            echo "macha-features: jq が無いので $dest には statusLine しか当てられない" >&2
        fi
    else
        [ -s "$dest" ] || echo '{}' > "$dest"
        local tmp
        tmp=$(mktemp)
        # .[0](既存) * .[1](テンプレート): テンプレートに無いキーは残し、あるキーは上書き
        if jq -s --argjson sl "$sl" '.[0] * .[1] | .statusLine = $sl' \
             "$dest" "$template" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$dest"
        else
            rm -f "$tmp"
            echo "macha-features: $dest が JSON として読めないので設定を当てない" >&2
            return 0
        fi
    fi
    chown "$uid:$gid" "$dest"
    chmod 600 "$dest"
}

# 静的な設定なのでマージ不要。symlink だけで rebuild のたびに最新になる
apply_claude_keybindings() {
    local dest="$STATE/claude/keybindings.json"
    local template="$SHARE/claude-keybindings.json"
    [ -f "$template" ] || return 0

    ln -sfn "$template" "$dest"
    chown -h "$uid:$gid" "$dest"
}

if [ "${CLAUDE:-false}" = "true" ]; then
    apply_json_config "$STATE/claude/settings.json" \
                      "$SHARE/claude-settings.json" \
                      "$SHARE/claude-statusline.sh" 1
    apply_claude_keybindings
fi

# Copilot 側は放っておくと古くなる表示が無いので refreshInterval は付けない
if [ "${COPILOT:-false}" = "true" ]; then
    apply_json_config "$STATE/copilot/settings.json" \
                      "$SHARE/copilot-settings.json" \
                      "$SHARE/copilot-statusline.sh" ""
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
