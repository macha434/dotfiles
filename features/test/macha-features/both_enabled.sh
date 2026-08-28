#!/usr/bin/env bash
# claude と codex を両方有効にした場合。
set -e
source dev-container-features-test-lib

STATE=/var/lib/agent-state

for name in claude codex; do
    check "$name の実体がある"    test -d "$STATE/$name"
    check "$name の symlink がある" test -L "/home/vscode/.$name"
    check "$name のリンク先が正しい" \
        bash -c "[ \"\$(readlink /home/vscode/.$name)\" = $STATE/$name ]"
    check "$name の所有者が vscode" \
        bash -c "[ \"\$(stat -c %U $STATE/$name)\" = vscode ]"
done

check "entrypoint が両方を知っている" \
    bash -c 'grep -q "AGENTS=(claude codex)" /usr/local/share/agent-state/entrypoint.sh'

reportResults
