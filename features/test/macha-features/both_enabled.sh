#!/usr/bin/env bash
# claude と codex を両方有効にした場合。
set -e
source dev-container-features-test-lib

check "claude CLI が入っている" test -x /home/vscode/.local/bin/claude
check "claude が起動する"       bash -c '/home/vscode/.local/bin/claude --version | grep -q "Claude Code"'

# codex は entrypoint が volume に入れるので、ランチャの解決先まで見る
check "codex のランチャがある"  test -L /home/vscode/.local/bin/codex
check "codex のリンクが解決する" \
    bash -c '[ -x "$(readlink -f /home/vscode/.local/bin/codex)" ]'
check "codex の実体が volume にある" \
    bash -c 'readlink -f /home/vscode/.local/bin/codex | grep -q "^/var/lib/agent-state/codex/"'
check "codex が起動する"        bash -c '/home/vscode/.local/bin/codex --version | grep -q codex'

for a in claude codex copilot; do
    check "$a の symlink がある" test -L "/home/vscode/.$a"
    check "$a の所有者が vscode" \
        bash -c "[ \"\$(stat -c %U /var/lib/agent-state/$a)\" = vscode ]"
done

check "copilot CLI は入っていない" bash -c '[ ! -e /home/vscode/.local/bin/copilot ]'

check "config が claude と codex だけ true で焼かれている" \
    bash -c 'grep -q "^CLAUDE=true$" /usr/local/share/macha-features/config \
             && grep -q "^CODEX=true$" /usr/local/share/macha-features/config \
             && grep -q "^COPILOT=false$" /usr/local/share/macha-features/config'

# codex/config.toml は claude/settings.json と違い、$STATE/codex/config.toml に
# 無いときだけ ensure-codex.sh (postCreate) が置く。
# features/src/macha-features/ensure-codex.sh 参照。
check "codex の config.toml がある" test -f /var/lib/agent-state/codex/config.toml
check "config.toml に model が入っている" \
    bash -c 'grep -q "^model = \"gpt-5.6-terra\"\$" /var/lib/agent-state/codex/config.toml'
check "config.toml に approval_policy が入っている" \
    bash -c 'grep -q "^approval_policy = \"on-request\"\$" /var/lib/agent-state/codex/config.toml'
check "config.toml に sandbox_mode が入っている" \
    bash -c 'grep -q "^sandbox_mode = \"danger-full-access\"\$" /var/lib/agent-state/codex/config.toml'
check "config.toml に vim_mode_default が入っている" \
    bash -c 'grep -q "^vim_mode_default = true\$" /var/lib/agent-state/codex/config.toml'

reportResults
