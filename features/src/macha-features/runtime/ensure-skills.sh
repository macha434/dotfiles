#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る (ensure-codex.sh の後)。
# 各 *Skills option が true なら、対応するカタログの全エントリを冪等に入れる。
set -eu

# shellcheck source=/dev/null
. /usr/local/share/macha-features/lib/common.sh
# shellcheck source=/dev/null
. "$SHARE/config"
# shellcheck source=/dev/null
. "$SHARE/lib/skills.sh"

# postCreateCommand がログインシェル経由とは限らないため PATH を明示する
export PATH="$HOME/.local/bin:$PATH"

if [ "${CLAUDE:-false}" = "true" ] && [ "${CLAUDE_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/claude-skills.json" install_claude_skill
fi

if [ "${CODEX:-false}" = "true" ] && [ "${CODEX_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/codex-skills.json" install_codex_skill
fi

if [ "${COPILOT:-false}" = "true" ] && [ "${COPILOT_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/copilot-skills.json" install_copilot_skill
fi
