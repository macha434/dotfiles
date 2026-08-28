#!/usr/bin/env bash
# 既定の option (claude のみ有効) で検査する。
#
# devcontainer features test は feature の mounts も適用するので、ここでの
# /var/lib/agent-state は実際に volume である。ローカルで回すと agent-state
# volume が残るため、docker volume rm agent-state で片付けること。
#
# ただし永続化・共有・別 uid からの復旧はここでは見ていない。
# docs/agent-state-feature-plan.md の Step 5 を別途通すこと。
set -e
source dev-container-features-test-lib

STATE=/var/lib/agent-state
HOME_DIR=/home/vscode

check "state ディレクトリがある"      test -d "$STATE"
check "所有者が vscode"               bash -c '[ "$(stat -c %U /var/lib/agent-state)" = vscode ]'
check "パーミッションが 700"          bash -c '[ "$(stat -c %a /var/lib/agent-state)" = 700 ]'
check "claude の実体がある"           test -d "$STATE/claude"
check "claude の symlink がある"      test -L "$HOME_DIR/.claude"
check "リンク先が正しい"              bash -c '[ "$(readlink /home/vscode/.claude)" = /var/lib/agent-state/claude ]'
check "codex は既定で無効"            bash -c '[ ! -e /home/vscode/.codex ]'
check "entrypoint が実行可能"         test -x /usr/local/share/agent-state/entrypoint.sh
check "entrypoint の構文が妥当"       bash -n /usr/local/share/agent-state/entrypoint.sh

reportResults
