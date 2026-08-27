#!/usr/bin/env bash
# dotfiles をこのマシンに配置する。
#
#   ./install.sh              すべて配置する
#   ./install.sh vscode       指定したものだけ配置する
#   ./install.sh --dry-run    何をするかだけ表示する
#   ./install.sh --list       配置できるものを一覧する
#
# ツールごとの手順は install.d/<名前>.sh に置く。ここに足せば自動で拾われる。
set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DOTFILES_ROOT

# shellcheck source=lib/common.sh
. "$DOTFILES_ROOT/lib/common.sh"

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

modules() {
    local path
    for path in "$DOTFILES_ROOT"/install.d/*.sh; do
        [ -e "$path" ] || continue
        basename "$path" .sh
    done
}

DRY_RUN=0
selected=()
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -l|--list)    modules; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        -*)           die "知らないオプション: $1 (--help)" ;;
        *)            selected+=("$1") ;;
    esac
    shift
done
export DRY_RUN

detect_os
if [ "$DRY_RUN" = 1 ]; then
    step "$DOTFILES_OS で実行中 (dry-run)"
else
    step "$DOTFILES_OS で実行中"
fi

# 指定されたものが実在するか先に確かめる
available=$(modules)
for name in ${selected[@]+"${selected[@]}"}; do
    printf '%s\n' "$available" | grep -qx -- "$name" \
        || die "そんなものは無い: $name (--list で一覧)"
done

failed=()
ran=0
for name in $available; do
    if [ ${#selected[@]} -gt 0 ] \
        && ! printf '%s\n' "${selected[@]}" | grep -qx -- "$name"; then
        continue
    fi
    step "$name"
    ran=$((ran + 1))
    # 1 つが失敗しても残りは続ける。副シェルなので変数も汚さない。
    if ! ( set -euo pipefail; . "$DOTFILES_ROOT/install.d/$name.sh" ); then
        warn "$name は失敗した"
        failed+=("$name")
    fi
done

[ "$ran" -gt 0 ] || die "配置するものが無い (--list で一覧)"

if [ ${#failed[@]} -gt 0 ]; then
    die "失敗: ${failed[*]}"
fi
step "完了"
