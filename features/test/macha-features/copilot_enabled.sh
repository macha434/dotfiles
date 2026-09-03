#!/usr/bin/env bash
# copilot だけを有効にした場合。claude=false なので、jq と設定マージが
# claude に引きずられずに copilot 単独で成立しているかも同時に見ている。
set -e
source dev-container-features-test-lib

STATE=/var/lib/agent-state
SHARE=/usr/local/share/macha-features

# Codex と違い Copilot は volume の外 (~/.local と ~/.cache) に入るので、
# ビルド時に入れている。ランチャは実体で symlink ではない。
check "copilot CLI が入っている" test -x /home/vscode/.local/bin/copilot
check "copilot が起動する" \
    bash -c '/home/vscode/.local/bin/copilot --version | grep -q "GitHub Copilot CLI"'
check "copilot の本体が volume の外にある" \
    bash -c '[ ! -e /var/lib/agent-state/copilot/pkg ]'

check "claude CLI は入っていない" bash -c '[ ! -e /home/vscode/.local/bin/claude ]'

# symlink は option に関わらず 3 つとも張る
for a in claude codex copilot; do
    check "$a の symlink がある" test -L "/home/vscode/.$a"
done

check "config が copilot だけ true で焼かれている" \
    bash -c 'grep -q "^CLAUDE=false$" /usr/local/share/macha-features/config \
             && grep -q "^COPILOT=true$" /usr/local/share/macha-features/config'

# jq は claude が false でも copilot のために要る
# (features/src/macha-features/install.sh 参照)
check "jq が入っている" command -v jq

# --- config.json は毎起動テンプレートとマージされる ---
# copilot/config.json 側の値と 1:1 で見る。値を変えたらこの対応も直すこと。
CFG=$STATE/copilot/config.json
check "config.json がある" test -f "$CFG"
check "config.json に model が入っている" \
    bash -c '[ "$(jq -r .model '"$CFG"')" = auto ]'
check "config.json に effortLevel が入っている" \
    bash -c '[ "$(jq -r .effortLevel '"$CFG"')" = high ]'
check "config.json に editorMode が入っている" \
    bash -c '[ "$(jq -r .editorMode '"$CFG"')" = vim ]'
check "config.json に experimental が入っている" \
    bash -c '[ "$(jq -r .experimental '"$CFG"')" = true ]'
check "config.json に defaultPermissionMode が入っている" \
    bash -c '[ "$(jq -r .defaultPermissionMode '"$CFG"')" = assisted ]'
check "config.json に includeCoAuthoredBy が入っている" \
    bash -c '[ "$(jq -r .includeCoAuthoredBy '"$CFG"')" = false ]'

# statusLine だけはテンプレートの ~/.copilot/... ではなくイメージ側の実体を指す
check "config.json の statusLine がイメージ側を指す" \
    bash -c '[ "$(jq -r .statusLine.command '"$CFG"')" \
              = /usr/local/share/macha-features/copilot-statusline.sh ]'
# Claude と違い refreshInterval は付けない (レート制限の残り時間表示が無いため)
check "config.json に refreshInterval は無い" \
    bash -c '[ "$(jq -r ".statusLine.refreshInterval // empty" '"$CFG"')" = "" ]'

# --- statusline ---
SL=$SHARE/copilot-statusline.sh
check "statusline スクリプトがある" test -x "$SL"
check "statusline が 2 行出す" \
    bash -c 'echo "{}" | '"$SL"' | wc -l | grep -qx 2'
check "statusline がモデル ID を出す" \
    bash -c 'echo "{\"model\":{\"id\":\"claude-sonnet-5\"}}" | '"$SL"' \
             | sed "s/\x1b\[[0-9;]*m//g" | grep -q claude-sonnet-5'
check "statusline がコンテキスト率を出す" \
    bash -c 'echo "{\"context_window\":{\"current_context_used_percentage\":42}}" | '"$SL"' \
             | sed "s/\x1b\[[0-9;]*m//g" | grep -q "ctx 42%"'
check "コンテキスト率が 90% 以上で赤になる" \
    bash -c 'echo "{\"context_window\":{\"current_context_used_percentage\":95}}" | '"$SL"' \
             | head -1 | grep -qP "\x1b\[31m"'
check "allow-all が有効なら赤で出る" \
    bash -c 'echo "{\"allow_all_enabled\":true}" | '"$SL"' | head -1 | grep -qP "\x1b\[31m"'
check "消費が出る" \
    bash -c 'echo "{\"ai_used\":{\"formatted\":\"1.25\"},\"cost\":{\"total_premium_requests\":7}}" \
             | '"$SL"' | tail -1 | sed "s/\x1b\[[0-9;]*m//g" | grep -q "ai 1.25"'
check "フィールドが無くても落ちない" \
    bash -c 'echo "{}" | '"$SL"' >/dev/null'

reportResults
