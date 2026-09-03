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

# claude/settings.json と copilot/config.json は volume の中にあり、コピーアップは
# 初回しか起きない。ビルド時に書くと 2 回目以降のコンテナに届かないので、毎起動
# ここで当てる。どちらも CLI 自身が書き戻す生きた設定なので扱いは同じ。
#
# 正はホスト側のファイル (テンプレートとして $SHARE に複製済み) だが、その
# statusLine はホスト向けの ~/.<agent>/statusline-command.sh を指しており、この
# イメージには存在しない。テンプレートを丸ごと当てたあと、statusLine だけを
# イメージ側の不変パスへ強制的に差し替える。
#
#   $1 volume 側の設定ファイル
#   $2 $SHARE のテンプレート
#   $3 $SHARE の statusline スクリプト
#   $4 refreshInterval の秒数 (空なら付けない)
apply_json_config() {
    local dest=$1 template=$2 script=$3 refresh=$4
    [ -f "$template" ] || return 0
    [ -x "$script" ] || return 0

    # 差し替える statusLine。refreshInterval はレート制限の残り時間を進めるために
    # 要る (イベント駆動だけだとアイドル中に表示が止まる) が、そういう表示を
    # 持たない側では付けない。
    local sl
    if [ -n "$refresh" ]; then
        sl=$(printf '{"type":"command","command":"%s","refreshInterval":%s}' "$script" "$refresh")
    else
        sl=$(printf '{"type":"command","command":"%s"}' "$script")
    fi

    if ! command -v jq >/dev/null 2>&1; then
        # テンプレートとのマージには jq が要る。無い環境では既存を壊さないよう、
        # ファイルが無いときだけ statusLine だけの最小構成を書く。
        if [ ! -e "$dest" ]; then
            printf '{"statusLine":%s}\n' "$sl" > "$dest"
            echo "macha-features: jq が無いので $dest には statusLine しか当てられない" >&2
        fi
    else
        [ -s "$dest" ] || echo '{}' > "$dest"
        local tmp
        tmp=$(mktemp)
        # .[0] (既存) * .[1] (テンプレート) で、テンプレートに無いキー
        # (CLI 自身が足したもの) は残しつつ、テンプレートにあるキーは上書きする。
        # host 側の install_file (symlink で単純上書き) と同じ力関係を、
        # volume を跨げないのでマージで再現している。
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
    apply_json_config "$STATE/claude/settings.json" \
                      "$SHARE/claude-settings.json" \
                      "$SHARE/claude-statusline.sh" 1
    apply_claude_keybindings
fi

# Copilot 側に refreshInterval を渡さないのは、ステータスラインにレート制限の
# 残り時間のような、放っておくと古くなる表示が無いため。Copilot の JSON には
# 窓ごとの上限も reset 時刻も入らない (copilot/statusline-command.sh の頭を参照)。
if [ "${COPILOT:-false}" = "true" ]; then
    apply_json_config "$STATE/copilot/config.json" \
                      "$SHARE/copilot-config.json" \
                      "$SHARE/copilot-statusline.sh" ""
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
