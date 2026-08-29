#!/usr/bin/env bash
# Codex CLI のユーザー設定を配置する。
#
# 設置先 (すべての OS):
#   ~/.codex/
#
# claude.sh と同じで、Codex も自分が動いている環境のホームを見る。WSL から
# 使うなら設置先も WSL 側の ~/.codex なので、OS ごとの分岐は要らない。
# CODEX_HOME を設定している場合はそちらが優先されるため、その環境では
# 手動で配置するか CODEX_HOME を ~/.codex に向けること。
#
# config.toml は Codex 自身も書き換える。TUI での設定変更や、一度きりの
# 案内を閉じたかどうかが永続化される。claude/settings.json と同じく
# install_file で単純に上書きするので、再実行すると Codex 自身が書いた分は
# 消える。Linux / macOS では symlink なので、書き戻しはこのリポジトリの
# 作業ツリーに直接現れる。

install_file "$DOTFILES_ROOT/codex/config.toml" \
             "$HOME/.codex/config.toml"
