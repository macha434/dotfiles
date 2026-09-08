#!/usr/bin/env bash
# GitHub Copilot CLI のユーザー設定 (settings.json / statusline) を ~/.copilot/ に配置する。
# Claude との設定対応表は features/src/macha-features/README.md 参照。

install_file "$DOTFILES_ROOT/copilot/statusline-command.sh" \
             "$HOME/.copilot/statusline-command.sh"
install_file "$DOTFILES_ROOT/copilot/settings.json" \
             "$HOME/.copilot/settings.json"

if [ "${DRY_RUN:-0}" != 1 ] && ! command -v jq >/dev/null 2>&1; then
    warn "jq が無い。ステータスラインは値が入らずプレースホルダーのままになる"
fi
