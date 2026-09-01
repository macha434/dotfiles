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

# settings.json は volume の中にあり、コピーアップは初回しか起きない。ビルド時に
# 書くと 2 回目以降のコンテナに届かないので、毎起動ここで当てる。
#
# 正はホスト側の claude/settings.json (テンプレートとして $SHARE に複製済み) だが、
# その statusLine はホスト向けの ~/.claude/statusline-command.sh を指しており、
# このイメージには存在しない。テンプレートを丸ごと当てたあと、statusLine だけを
# イメージ側の不変パスへ強制的に差し替える。
apply_claude_settings() {
    local settings="$STATE/claude/settings.json"
    local template="$SHARE/claude-settings.json"
    local script="$SHARE/claude-statusline.sh"
    [ -f "$template" ] || return 0
    [ -x "$script" ] || return 0

    if ! command -v jq >/dev/null 2>&1; then
        # テンプレートとのマージには jq が要る。無い環境では既存を壊さないよう、
        # settings.json が無いときだけ statusLine だけの最小構成を書く。
        if [ ! -e "$settings" ]; then
            printf '{"statusLine":{"type":"command","command":"%s","refreshInterval":1}}\n' \
                "$script" > "$settings"
            echo "macha-features: jq が無いので $settings には statusLine しか当てられない" >&2
        fi
    else
        [ -s "$settings" ] || echo '{}' > "$settings"
        local tmp
        tmp=$(mktemp)
        # .[0] (既存) * .[1] (テンプレート) で、テンプレートに無いキー
        # (Claude Code 自身が足したもの) は残しつつ、テンプレートにあるキーは
        # 上書きする。host 側の install_file (symlink で単純上書き) と同じ
        # 力関係を、volume を跨げないのでマージで再現している。
        # refreshInterval はレート制限の残り時間を進めるために要る。
        # イベント駆動だけだとアイドル中に表示が止まる。
        if jq -s --arg cmd "$script" \
             '.[0] * .[1] | .statusLine = {type: "command", command: $cmd, refreshInterval: 1}' \
             "$settings" "$template" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$settings"
        else
            rm -f "$tmp"
            echo "macha-features: $settings が JSON として読めないので設定を当てない" >&2
            return 0
        fi
    fi
    chown "$uid:$gid" "$settings"
    chmod 600 "$settings"
}

# keybindings.json は Claude Code 自身が書き換えることの無い静的な設定なので、
# settings.json と違ってマージは要らない。volume の外 (イメージ側) を指す symlink
# にしておけば、jq に頼らず、再ビルドのたびに最新の内容になる。
apply_claude_keybindings() {
    local dest="$STATE/claude/keybindings.json"
    local template="$SHARE/claude-keybindings.json"
    [ -f "$template" ] || return 0

    ln -sfn "$template" "$dest"
    chown -h "$uid:$gid" "$dest"
}

if [ "${CLAUDE:-false}" = "true" ]; then
    apply_claude_settings
    apply_claude_keybindings
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
