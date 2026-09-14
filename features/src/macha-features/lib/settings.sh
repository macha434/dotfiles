# 起動毎に settings.json テンプレートを既存設定へマージし、statusLine を強制上書きする
#
#   $1 volume 側の設定ファイル
#   $2 $SHARE のテンプレート
#   $3 $SHARE の statusline スクリプト
#   $4 refreshInterval の秒数 (空なら付けない)
apply_json_config() {
    local dest=$1 template=$2 script=$3 refresh=$4
    [ -f "$template" ] || return 0
    [ -x "$script" ] || return 0

    local sl
    if [ -n "$refresh" ]; then
        sl=$(printf '{"type":"command","command":"%s","refreshInterval":%s}' "$script" "$refresh")
    else
        sl=$(printf '{"type":"command","command":"%s"}' "$script")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        if [ ! -e "$dest" ]; then
            printf '{"statusLine":%s}\n' "$sl" > "$dest"
            echo "macha-features: jq が無いので $dest には statusLine しか当てられない" >&2
        fi
    else
        [ -s "$dest" ] || echo '{}' > "$dest"
        local tmp
        tmp=$(mktemp)
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

# keybindings.json を $SHARE のテンプレートへの symlink にする
apply_claude_keybindings() {
    local dest="$STATE/claude/keybindings.json"
    local template="$SHARE/claude-keybindings.json"
    [ -f "$template" ] || return 0

    ln -sfn "$template" "$dest"
    chown -h "$uid:$gid" "$dest"
}
