#!/usr/bin/env bash
# GitHub Copilot CLI のユーザー設定を配置する。
#
# 設置先 (すべての OS):
#   ~/.copilot/
#
# claude.sh / codex.sh と同じで、Copilot も自分が動いている環境のホームを見る。
# COPILOT_HOME を設定している場合はそちらが優先されるため、その環境では手動で
# 配置するか COPILOT_HOME を ~/.copilot に向けること。
#
# config.json は Copilot 自身も書き換える (/model /theme /vim /settings や
# trustedFolders、--no-mouse など)。claude/settings.json と同じく install_file
# で単純に上書きするので、再実行すると Copilot 自身が書いた分は消える。
#
# ---- claude/settings.json との対応 --------------------------------------
# 「できるだけ Claude と同じ」を JSON にしたのが copilot/config.json で、
# 対応関係と、対応するものが無いキーは次のとおり。config.json 自体は素の JSON
# でコメントを書けないので、対応表はここに置いている。
#
#   Claude                          Copilot
#   ------------------------------  --------------------------------------
#   model: "sonnet"                 model: "claude-sonnet-5"
#       Codex と同じく、常に最新へ解決されるファミリーエイリアスが無いので
#       モデル ID を直接指定する。新しい版が出たらここを更新する。
#   alwaysThinkingEnabled: true     (effortLevel に含まれる)
#   effortLevel: "high"             effortLevel: "high"
#       Copilot も常に推論するため、有無ではなく深さの指定になる。
#       none / minimal / low / medium / high / xhigh / max を取る。
#   editorMode: "vim"               editorMode: "vim"
#       キー名まで同じ。ただし後述の experimental が要る。
#   permissions.defaultMode: "auto" defaultPermissionMode: "assisted"
#       assisted は「安全と判断したものだけ自動承認し、それ以外は訊く」で、
#       Claude の auto と同じ考え方。全部通す allow-all は Claude で言えば
#       bypassPermissions のほうなので選んでいない。これも experimental が要る。
#   attribution.commit: ""          includeCoAuthoredBy: false
#       Copilot は Co-authored-by トレーラだけなので、これで消える。
#   statusLine.command              statusLine.command
#       type / command / refreshInterval / padding までスキーマが同じ。
#       ただし stdin に渡る JSON の中身は違うので、スクリプトは別に要る
#       (copilot/statusline-command.sh の頭を参照)。
#
# 対応するものが無くて設定していないもの:
#
#   theme: "dark"
#       Copilot のテーマは default / github / dim / high-contrast / colorblind
#       で、dark を固定する手段が無い。github だけが専用の配色 (GitHub Dark /
#       Light) を持つが、端末に配色を問い合わせて明暗を自動で切り替える。
#       default と dim は端末の 16 色をそのまま使う。ダークに寄せたいなら
#       端末側をダークにするしかないので、既定でもある github にしている。
#   tui: "fullscreen"
#       Copilot は TUI 起動時に必ず alt screen へ入る。設定項目が無いのは
#       常にそうなっているからで、Claude と同じ挙動になっている。
#   fastMode / fastModePerSessionOptIn
#       fast mode に相当する仕組みが無い。速い版が要るならモデル ID の側で
#       選ぶ (claude-opus-4.8-fast など)。
#   attribution.pr / attribution.sessionUrl
#       PR 本文への署名に相当する設定が無い。
#
# experimental: true を入れているのは上の 2 つ (editorMode と
# defaultPermissionMode) のためで、Claude 側に対応するキーがあるわけではない。
# どちらも実験機能のフラグ越しに有効化されるので、これが無いと黙って効かない。
# フラグが下りていない環境では defaultPermissionMode は警告を出して manual に
# フォールバックし、editorMode は無視される (設定自体はエラーにならない)。

install_file "$DOTFILES_ROOT/copilot/statusline-command.sh" \
             "$HOME/.copilot/statusline-command.sh"
install_file "$DOTFILES_ROOT/copilot/config.json" \
             "$HOME/.copilot/config.json"

# claude.sh と同じ理由。statusline-command.sh は jq で JSON を読むので、
# 無いと値が入らずプレースホルダー (ctx -- / ai --) のままになる。
if [ "${DRY_RUN:-0}" != 1 ] && ! command -v jq >/dev/null 2>&1; then
    warn "jq が無い。ステータスラインは値が入らずプレースホルダーのままになる"
fi
