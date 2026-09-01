#!/usr/bin/env bash
# 既定の option (claude=true, codex=false) で検査する。
#
# devcontainer features test は feature の mounts も entrypoint も適用するので、
# ここでの /var/lib/agent-state は実際に volume で、statusline も当たった後。
# ローカルで回すと agent-state volume が残るため
# docker volume rm agent-state で片付けること。
#
# 永続化・共有・別 uid からの復旧はここでは見ていない。
# docs/agent-state-feature-plan.md の Step 5 を別途通すこと。
set -e
source dev-container-features-test-lib

STATE=/var/lib/agent-state
SHARE=/usr/local/share/macha-features

# --- volume と symlink は option に関わらず両方 ---
check "state の所有者が vscode"   bash -c '[ "$(stat -c %U /var/lib/agent-state)" = vscode ]'
check "state のパーミッションが 700" bash -c '[ "$(stat -c %a /var/lib/agent-state)" = 700 ]'
for a in claude codex; do
    check "$a の実体がある"        test -d "$STATE/$a"
    check "$a の symlink がある"   test -L "/home/vscode/.$a"
    check "$a のリンク先が正しい" \
        bash -c "[ \"\$(readlink /home/vscode/.$a)\" = $STATE/$a ]"
done

# ~/.claude.json (oauthAccount を含むグローバル設定) は ~/.claude の外にあり、
# 別途ファイルとして symlink している。無いと再ログインを求められ続ける。
check "~/.claude.json の symlink がある" test -L /home/vscode/.claude.json
check "~/.claude.json のリンク先が正しい" \
    bash -c '[ "$(readlink /home/vscode/.claude.json)" = /var/lib/agent-state/claude/.claude.json ]'

# --- CLI は option どおり ---
check "claude CLI が入っている"    test -x /home/vscode/.local/bin/claude
check "codex CLI は入っていない"   bash -c '[ ! -e /home/vscode/.local/bin/codex ]'
check "codex のバイナリも入っていない" \
    bash -c '[ ! -e /var/lib/agent-state/codex/packages ]'

# --- statusline ---
check "statusline スクリプトがある" test -x "$SHARE/claude-statusline.sh"
check "settings.json に statusLine が入っている" \
    bash -c '[ "$(jq -r .statusLine.command /var/lib/agent-state/claude/settings.json)" \
              = /usr/local/share/macha-features/claude-statusline.sh ]'
check "settings.json に refreshInterval 1 が入っている" \
    bash -c '[ "$(jq -r .statusLine.refreshInterval /var/lib/agent-state/claude/settings.json)" = 1 ]'

# --- settings.json / keybindings.json はテンプレート全体を反映する ---
# claude/settings.json 側の値と 1:1 で見る。値そのものを変えたら、この対応も直すこと。
check "settings.json に model が入っている" \
    bash -c '[ "$(jq -r .model /var/lib/agent-state/claude/settings.json)" = sonnet ]'
check "settings.json に editorMode が入っている" \
    bash -c '[ "$(jq -r .editorMode /var/lib/agent-state/claude/settings.json)" = vim ]'
check "settings.json に theme が入っている" \
    bash -c '[ "$(jq -r .theme /var/lib/agent-state/claude/settings.json)" = dark ]'
check "settings.json に permissions.defaultMode が入っている" \
    bash -c '[ "$(jq -r .permissions.defaultMode /var/lib/agent-state/claude/settings.json)" = auto ]'
check "settings.json に attribution.commit が空文字で入っている" \
    bash -c '[ "$(jq -r .attribution.commit /var/lib/agent-state/claude/settings.json)" = "" ]'
check "settings.json テンプレートが SHARE に置かれている" \
    test -f "$SHARE/claude-settings.json"

check "keybindings.json の symlink がある" test -L /home/vscode/.claude/keybindings.json
check "keybindings.json のリンク先が SHARE を指す" \
    bash -c '[ "$(readlink /home/vscode/.claude/keybindings.json)" = /usr/local/share/macha-features/claude-keybindings.json ]'
check "keybindings.json の内容がリポジトリと一致する" \
    diff /home/vscode/.claude/keybindings.json /usr/local/share/macha-features/claude-keybindings.json
# statusline は 3 行構成。ANSI を落として中身を見る。
SL=/usr/local/share/macha-features/claude-statusline.sh
check "statusline が 3 行出す" \
    bash -c 'echo "{}" | '"$SL"' | wc -l | grep -qx 3'
check "statusline がモデル ID を出す" \
    bash -c 'echo "{\"model\":{\"id\":\"claude-opus-5\"}}" | '"$SL"' \
             | sed "s/\x1b\[[0-9;]*m//g" | grep -q claude-opus-5'
check "statusline がコンテキスト率を出す" \
    bash -c 'echo "{\"context_window\":{\"used_percentage\":42}}" | '"$SL"' \
             | sed "s/\x1b\[[0-9;]*m//g" | grep -q "ctx 42%"'
# 5 時間窓で 2 時間経過 (残り 3 時間) なら、線形ペースは 40%。
# 45% はそれを超えるので赤、25% は 30% も下回るので緑。
check "レート制限がペース超過で赤になる" \
    bash -c 'echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":45,\"resets_at\":$(($(date +%s)+10800))}}}" \
             | '"$SL"' | tail -1 | grep -qP "\x1b\[31m"'
check "レート制限がペース内で緑になる" \
    bash -c 'echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":25,\"resets_at\":$(($(date +%s)+10800))}}}" \
             | '"$SL"' | tail -1 | grep -qP "\x1b\[32m"'
check "rate_limits が無くても落ちない" \
    bash -c 'echo "{}" | '"$SL"' >/dev/null'

check "entrypoint が実行可能"      test -x "$SHARE/entrypoint.sh"
check "PATH に ~/.local/bin が入る" \
    bash -lc 'case ":$PATH:" in *":$HOME/.local/bin:"*) exit 0;; *) exit 1;; esac'

reportResults
