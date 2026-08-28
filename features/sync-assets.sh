#!/usr/bin/env bash
# dotfiles 本体で管理しているファイルを feature ディレクトリへ複製する。
#
#   ./features/sync-assets.sh            複製する
#   ./features/sync-assets.sh --list     対応表を表示する
#   ./features/sync-assets.sh --verify   設定漏れを検査する (CI 用)
#
# なぜコピーが要るか: feature の tarball には feature ディレクトリ配下しか入らない。
# しかも packaging は symlink を symlink のまま tar に入れるので、リポジトリ内 symlink で
# 共有すると公開された feature が宙を指すリンクを抱える (実測で確認)。
#
# 対応を増やすときは features/assets.tsv に 1 行足すだけでよい。足したあと --verify を
# 通せば、workflow の paths と .gitignore の漏れをその場で教えてくれる。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/features/assets.tsv"
WORKFLOW="$ROOT/.github/workflows/features.yaml"

die() { printf 'sync-assets: %s\n' "$*" >&2; exit 1; }

# コメントと空行を落として <source> <destination> の組を吐く
entries() {
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$MANIFEST"
}

do_sync() {
    local src dst n=0
    while read -r src dst; do
        [ -f "$ROOT/$src" ] || die "元ファイルが無い: $src"
        mkdir -p "$ROOT/$(dirname "$dst")"
        # 実行ビットを含めて元の mode をそのまま持っていく
        install -m "$(stat -c %a "$ROOT/$src")" "$ROOT/$src" "$ROOT/$dst"
        printf '  %s -> %s\n' "$src" "$dst"
        n=$((n + 1))
    done < <(entries)
    printf 'sync-assets: %d 件を複製した\n' "$n"
}

do_list() {
    printf '%-32s %s\n' "SOURCE" "DESTINATION"
    while read -r src dst; do
        printf '%-32s %s\n' "$src" "$dst"
    done < <(entries)
}

# 対応表に足したのに他を直し忘れた、を検出する
do_verify() {
    local src dst bad=0
    while read -r src dst; do
        if [ ! -f "$ROOT/$src" ]; then
            printf '  NG  元ファイルが無い: %s\n' "$src" >&2; bad=1
        fi
        # source が変わったときに CI が起動しないと、複製が公開物に反映されない
        if ! grep -qF "$src" "$WORKFLOW"; then
            printf '  NG  workflow の paths に %s が無い\n' "$src" >&2; bad=1
        fi
        # destination は生成物なので追跡しない
        if ! git -C "$ROOT" check-ignore -q "$dst" 2>/dev/null; then
            printf '  NG  .gitignore が %s を無視していない\n' "$dst" >&2; bad=1
        fi
    done < <(entries)

    [ "$bad" = 0 ] || die "設定に漏れがある"
    printf 'sync-assets: 対応表と workflow / .gitignore は揃っている\n'
}

case "${1-}" in
    "")        do_sync ;;
    --list)    do_list ;;
    --verify)  do_verify ;;
    *)         die "知らないオプション: $1 (--list / --verify)" ;;
esac
