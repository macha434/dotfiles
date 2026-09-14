#!/usr/bin/env bash
# claudeSkills/codexSkills/copilotSkills を有効にした場合。カタログ
# (claude-skills.json / codex-skills.json)の各エントリが持つ repo から
# 実際にネットワーク越しに marketplace 追加 → インストールされるところ
# まで見る (現状どちらも macha434 配下だが、カタログの repo フィールドが
# 指すものなら誰のリポジトリでもよい)。copilot-skills.json は今のところ
# 空(該当プラグインが無い)なので、copilot 側は option の配線だけ見て、
# 実際のインストールは検査しない。
set -e
source dev-container-features-test-lib

SHARE=/usr/local/share/macha-features

check "config に skill オプションが焼かれている" \
    bash -c 'grep -q "^CLAUDE_SKILLS=true$" '"$SHARE"'/config \
             && grep -q "^CODEX_SKILLS=true$" '"$SHARE"'/config \
             && grep -q "^COPILOT_SKILLS=true$" '"$SHARE"'/config'

check "ensure-skills.sh が実行可能" test -x "$SHARE/ensure-skills.sh"

check "claude-skills.json が SHARE に置かれている" \
    bash -c '[ "$(jq -r ".[0].name" '"$SHARE"'/claude-skills.json)" = haiku-shunt ] \
             && [ "$(jq -r ".[0].repo" '"$SHARE"'/claude-skills.json)" = macha434/haiku-shunt ] \
             && [ "$(jq -r ".[0].marketplace" '"$SHARE"'/claude-skills.json)" = macha434-plugins ]'
check "codex-skills.json が SHARE に置かれている" \
    bash -c '[ "$(jq -r ".[0].name" '"$SHARE"'/codex-skills.json)" = luna-shunt ] \
             && [ "$(jq -r ".[0].repo" '"$SHARE"'/codex-skills.json)" = macha434/luna-shunt ] \
             && [ "$(jq -r ".[0].marketplace" '"$SHARE"'/codex-skills.json)" = macha434-plugins ]'
check "copilot-skills.json が SHARE に置かれている(空カタログ)" \
    bash -c '[ "$(jq -r "length" '"$SHARE"'/copilot-skills.json)" = 0 ]'

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

check "copilot CLI が入っている" test -x /home/vscode/.local/bin/copilot
check "copilotSkillsを有効にしてもカタログが空なら何も入らない" \
    bash -c '/home/vscode/.local/bin/copilot plugin list | grep -q "No plugins installed."'

reportResults
