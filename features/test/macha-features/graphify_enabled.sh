#!/usr/bin/env bash
# graphify を claude/codex と一緒に有効にした場合。CLI 導入 (ビルド時) と
# スキル登録 (postCreate、ensure-skills.sh) の両方が volume 経由で成立するか見る。
set -e
source dev-container-features-test-lib

SHARE=/usr/local/share/macha-features

check "config に graphify が焼かれている" \
    bash -c 'grep -q "^GRAPHIFY=true$" '"$SHARE"'/config'

check "uv が入っている" bash -c 'command -v /home/vscode/.local/bin/uv'
check "graphify CLI が入っている" test -x /home/vscode/.local/bin/graphify
check "graphify が起動する" \
    bash -c '/home/vscode/.local/bin/graphify --help | grep -q "graphify <command>"'

check "lib/graphify.sh が SHARE に置かれている" test -f "$SHARE/lib/graphify.sh"
check "ensure-skills.sh が実行可能" test -x "$SHARE/ensure-skills.sh"

# ensure-codex.sh の後に postCreateCommand として ensure-skills.sh が走っている前提。
# ~/.claude, ~/.codex は volume (/var/lib/agent-state) への symlink なので、
# skill が実際に永続化される側に書かれていることまで見る。
check "claude 向け skill が入っている" \
    test -f /home/vscode/.claude/skills/graphify/SKILL.md
check "claude 向け skill が volume 側の実体である" \
    test -f /var/lib/agent-state/claude/skills/graphify/SKILL.md
check "claude 向け CLAUDE.md が作られている" \
    test -f /home/vscode/.claude/CLAUDE.md

check "codex 向け skill が入っている" \
    test -f /home/vscode/.codex/skills/graphify/SKILL.md
check "codex 向け skill が volume 側の実体である" \
    test -f /var/lib/agent-state/codex/skills/graphify/SKILL.md

# このシナリオでは copilot を有効にしていないので、copilot 向けには何も登録されない
check "copilot 向けには何も登録されない" \
    bash -c '[ ! -e /var/lib/agent-state/copilot/skills/graphify ]'

reportResults
