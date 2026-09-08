#!/usr/bin/env bash
# herdr のユーザー設定を ~/.config/herdr/config.toml に配置する。
# CLI 本体はここではインストールしない (https://herdr.dev/docs/install/ 参照)。

install_file "$DOTFILES_ROOT/herdr/config.toml" \
             "$HOME/.config/herdr/config.toml"
