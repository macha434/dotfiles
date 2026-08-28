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
# claude/statusline-command.sh は .workspace.current_dir を読んで
# 「ディレクトリ名 (ブランチ)」を出す
check "statusline がディレクトリ名を出す" \
    bash -c 'echo "{\"workspace\":{\"current_dir\":\"/tmp\"}}" \
             | /usr/local/share/macha-features/claude-statusline.sh | grep -qx tmp'
check "statusline が git ブランチを出す" \
    bash -c 'cd /tmp && rm -rf slrepo && mkdir slrepo && cd slrepo \
             && git init -q -b main . \
             && echo "{\"workspace\":{\"current_dir\":\"/tmp/slrepo\"}}" \
                | /usr/local/share/macha-features/claude-statusline.sh \
                | grep -qx "slrepo (main)"'

check "entrypoint が実行可能"      test -x "$SHARE/entrypoint.sh"
check "PATH に ~/.local/bin が入る" \
    bash -lc 'case ":$PATH:" in *":$HOME/.local/bin:"*) exit 0;; *) exit 1;; esac'

reportResults
