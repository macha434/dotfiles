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

for a in claude codex; do
    check "$a の symlink がある" test -L "/home/vscode/.$a"
    check "$a の所有者が vscode" \
        bash -c "[ \"\$(stat -c %U /var/lib/agent-state/$a)\" = vscode ]"
done

check "config が両方 true で焼かれている" \
    bash -c 'grep -q "^CLAUDE=true$" /usr/local/share/macha-features/config \
             && grep -q "^CODEX=true$" /usr/local/share/macha-features/config'

reportResults
