#!/usr/bin/env bash
# Claude Code のユーザー設定を ~/.claude/ に配置する。
# Claude Code は自分が動いている環境のホームを見るため OS ごとの分岐は無い (vscode.sh と違う)。
# keybindings.json はモデルピッカーの enter を「このセッションのみ」にし、既定の書き戻しで symlink 先が汚れるのを防ぐ (s キーは従来どおり)。

install_file "$DOTFILES_ROOT/claude/statusline-command.sh" \
             "$HOME/.claude/statusline-command.sh"
install_file "$DOTFILES_ROOT/claude/settings.json" \
             "$HOME/.claude/settings.json"
install_file "$DOTFILES_ROOT/claude/keybindings.json" \
             "$HOME/.claude/keybindings.json"

if [ "${DRY_RUN:-0}" != 1 ] && ! command -v jq >/dev/null 2>&1; then
    warn "jq が無い。ステータスラインは値が入らずプレースホルダーのままになる"
fi
