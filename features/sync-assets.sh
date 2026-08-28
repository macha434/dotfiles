#!/usr/bin/env bash
# dotfiles 本体で管理しているファイルを feature ディレクトリへ複製する。
#
# feature の tarball には feature ディレクトリ配下しか入らない。しかも packaging は
# symlink を symlink のまま tar に入れるので、リポジトリ内 symlink で共有すると
# 公開された feature が宙を指すリンクを抱えることになる (実測で確認)。
# そのため実体のコピーが要る。正は claude/ 側で、こちらは生成物。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$ROOT/features/src/macha-features/statusline"

mkdir -p "$dest"
install -m 755 "$ROOT/claude/statusline-command.sh" "$dest/claude.sh"
echo "synced: claude/statusline-command.sh -> features/src/macha-features/statusline/claude.sh"
