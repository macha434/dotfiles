#!/usr/bin/env bash
# GitHub Copilot CLI のステータスライン。stdin にセッション情報の JSON が渡る。
# claude/statusline-command.sh と対になる内容。Claude 版との対応表は
# features/src/macha-features/README.md 参照。
set -uo pipefail

input=$(cat)
q() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'

model=$(q '.model.id')
allow=$(q '.allow_all_enabled')
# used_percentage は代替時のフォールバック値だがセッション累計で意味が違う。
pct=$(q '.context_window.current_context_used_percentage')
[ -n "$pct" ] || pct=$(q '.context_window.used_percentage')

line1="${BLU}${model:-?}${R}"

# allow-all は有効なほど危険なので、fast mode と逆に有効時を赤で強調する。
if [ "$allow" = "true" ]; then
    line1="$line1 ${D}·${R} ${RED}${B}allow-all${R}"
else
    line1="$line1 ${D}· allow-all off${R}"
fi

if [ -n "$pct" ]; then
    p=${pct%%.*}
    if   [ "$p" -ge 90 ]; then c=$RED
    elif [ "$p" -ge 70 ]; then c=$YEL
    else                       c=$GRN
    fi
    line1="$line1 ${D}·${R} ctx ${c}${p}%${R}"
else
    line1="$line1 ${D}· ctx --${R}"
fi
printf '%s\n' "$line1"

field() {
    local label=$1 value=$2
    if [ -z "$value" ]; then
        printf '%s' "${D}${label} --${R}"
    else
        printf '%s' "${D}${label}${R} ${value}"
    fi
}

printf '%s   %s\n' \
    "$(field ai      "$(q '.ai_used.formatted')")" \
    "$(field premium "$(q '.cost.total_premium_requests')")"
