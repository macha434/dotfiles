#!/usr/bin/env bash
# herdr だけを有効にした場合。claude/codex/copilot なしでも成立するか見る。
set -e
source dev-container-features-test-lib

check "herdr CLI が入っている" test -x /home/vscode/.local/bin/herdr
check "herdr が起動する" \
    bash -c '/home/vscode/.local/bin/herdr --version | grep -q herdr'

check "claude CLI は入っていない" bash -c '[ ! -e /home/vscode/.local/bin/claude ]'
check "codex CLI は入っていない"  bash -c '[ ! -e /home/vscode/.local/bin/codex ]'
check "copilot CLI は入っていない" bash -c '[ ! -e /home/vscode/.local/bin/copilot ]'

# symlink は option に関わらず claude/codex/copilot の 3 つだけ張る (herdr は対象外)
for a in claude codex copilot; do
    check "$a の symlink がある" test -L "/home/vscode/.$a"
done

check "config が herdr だけ true で焼かれている" \
    bash -c 'grep -q "^CLAUDE=false$" /usr/local/share/macha-features/config \
             && grep -q "^HERDR=true$" /usr/local/share/macha-features/config'

# herdr は volume 化しない。~/.config/herdr は普通のファイルで、$STATE には何も置かない
check "config.toml がある" test -f /home/vscode/.config/herdr/config.toml
check "config.toml は symlink ではない" bash -c '[ ! -L /home/vscode/.config/herdr/config.toml ]'
check "herdr は volume に何も置かない" bash -c '[ ! -e /var/lib/agent-state/herdr ]'
check "config.toml が正しく読める" \
    bash -c '/home/vscode/.local/bin/herdr config check | grep -q "config: ok"'

reportResults
