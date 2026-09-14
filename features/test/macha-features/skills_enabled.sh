#!/usr/bin/env bash
# claudeSkills/codexSkills を有効にした場合。カタログ(claude-skills.json /
# codex-skills.json)に載っている全プラグインが、ネットワーク越しに実際の
# macha434/haiku-shunt・macha434/luna-shunt リポジトリから marketplace 追加
# → インストールされるところまで見る。
set -e
source dev-container-features-test-lib

SHARE=/usr/local/share/macha-features

check "config に skill オプションが焼かれている" \
    bash -c 'grep -q "^CLAUDE_SKILLS=true$" '"$SHARE"'/config \
             && grep -q "^CODEX_SKILLS=true$" '"$SHARE"'/config'

check "ensure-skills.sh が実行可能" test -x "$SHARE/ensure-skills.sh"

check "claude-skills.json が SHARE に置かれている" \
    bash -c '[ "$(jq -r ".[0]" '"$SHARE"'/claude-skills.json)" = haiku-shunt ]'
check "codex-skills.json が SHARE に置かれている" \
    bash -c '[ "$(jq -r ".[0]" '"$SHARE"'/codex-skills.json)" = luna-shunt ]'

# ensure-codex.sh の後に postCreateCommand として ensure-skills.sh が走っている前提
check "claude marketplace macha434-plugins が追加されている" \
    bash -c '/home/vscode/.local/bin/claude plugin marketplace list --json \
             | jq -e "any(.[]; .name == \"macha434-plugins\")" >/dev/null'
check "claude plugin haiku-shunt が入っている" \
    bash -c '/home/vscode/.local/bin/claude plugin list --json \
             | jq -e "any(.[]; .id == \"haiku-shunt@macha434-plugins\")" >/dev/null'

check "codex marketplace macha434-plugins が追加されている" \
    bash -c 'PATH="/home/vscode/.local/bin:$PATH" codex plugin marketplace list --json \
             | jq -e "any(.marketplaces[]?; .name == \"macha434-plugins\")" >/dev/null'
check "codex plugin luna-shunt が入っている" \
    bash -c 'PATH="/home/vscode/.local/bin:$PATH" codex plugin list --json \
             | jq -e "any(.installed[]?; .pluginId == \"luna-shunt@macha434-plugins\")" >/dev/null'

reportResults
