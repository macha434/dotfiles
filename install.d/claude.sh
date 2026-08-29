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
# settings.json は Claude Code 自身も書き換える生きた設定 (MCP サーバーの
# 承認履歴など) だが、vscode.sh の settings.json と同じく install_file で
# 単純に上書きする。再実行すると Claude Code 自身が書いた分は消えるので、
# その運用で困る場合はこの行を外して手動管理に切り替える。
#
# keybindings.json はモデルピッカーの enter を「このセッションのみ」に倒す。
# 既定の enter は選んだモデルを settings.json へ書き戻すため、symlink 越しに
# このリポジトリが汚れる。s キー (既定) も従来どおり使える。

install_file "$DOTFILES_ROOT/claude/statusline-command.sh" \
             "$HOME/.claude/statusline-command.sh"
install_file "$DOTFILES_ROOT/claude/settings.json" \
             "$HOME/.claude/settings.json"
install_file "$DOTFILES_ROOT/claude/keybindings.json" \
             "$HOME/.claude/keybindings.json"
