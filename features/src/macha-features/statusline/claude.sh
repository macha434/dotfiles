#!/usr/bin/env bash
# Claude Code のステータスライン。stdin にセッション情報の JSON が渡る。
# 自分用の表示なので、いじるならこのファイルを直接編集して version を上げる。
set -uo pipefail

json=$(cat)
q() { printf '%s' "$json" | jq -r "$1 // empty" 2>/dev/null; }

model=$(q '.model.display_name')
dir=$(basename "$(q '.cwd')")
ctx=$(q '.context_window.used_percentage')

branch=$(git -C "$(q '.cwd')" branch --show-current 2>/dev/null)

out="${model:-?} ${dir}"
[ -n "$branch" ] && out="$out (${branch})"
[ -n "$ctx" ] && out="$out ${ctx%.*}%"

printf '%s' "$out"
