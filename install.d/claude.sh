#!/usr/bin/env bash
# Claude Code のユーザー設定を配置する。
#
# 設置先 (すべての OS):
#   ~/.claude/
#
# VS Code と違い、Claude Code は自分が動いている環境のホームを見る。WSL から
# 使うなら設置先も WSL 側の ~/.claude で、Windows 側に置く必要は無い。
# そのため vscode.sh のような OS ごとの分岐は要らない。
#
# settings.json は Claude Code 自身が書き換える生きた設定なので触らない。
# statusLine を有効にするには settings.json に次を足す:
#   "statusLine": { "type": "command", "command": "~/.claude/statusline-command.sh" }

install_file "$DOTFILES_ROOT/claude/statusline-command.sh" \
             "$HOME/.claude/statusline-command.sh"
