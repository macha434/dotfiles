#!/usr/bin/env bash
# Codex CLI のユーザー設定を ~/.codex/ に配置する。
# claude.sh と同じ理由で OS ごとの分岐は無い。CODEX_HOME を設定している場合はそちらが優先されるので、その環境では手動配置するか CODEX_HOME を ~/.codex に向けること。
# config.toml は Codex 自身も書き換えるが install_file で単純に上書きするため、再実行すると Codex が書いた分は消える。

install_file "$DOTFILES_ROOT/codex/config.toml" \
             "$HOME/.codex/config.toml"
