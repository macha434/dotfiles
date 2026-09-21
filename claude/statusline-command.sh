#!/usr/bin/env bash
# Claude Code のステータスライン。stdin にセッション情報の JSON が渡る。
# 表示内容・色分けロジックは features/src/macha-features/README.md 参照。
set -uo pipefail

input=$(cat)
q() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'

vim=$(q '.vim.mode')
case "$vim" in
    NORMAL)        printf '%s\n' "${GRN}${B}NORMAL${R}" ;;
    INSERT)        printf '%s\n' "${CYN}${B}INSERT${R}" ;;
    VISUAL*)       printf '%s\n' "${MAG}${B}${vim}${R}" ;;
    "")            printf '%s\n' "${D}(vim off)${R}" ;;
    *)             printf '%s\n' "${B}${vim}${R}" ;;
esac

model=$(q '.model.id')
effort=$(q '.effort.level')
fast=$(q '.fast_mode')
pct=$(q '.context_window.used_percentage')

line2="${BLU}${model:-?}${R}"

if [ -n "$effort" ]; then
    case "$effort" in
        high|max) c=$MAG ;;
        low)      c=$D ;;
        *)        c=$CYN ;;
    esac
    line2="$line2 ${D}·${R} ${c}${effort}${R}"
fi

if [ "$fast" = "true" ]; then
    line2="$line2 ${D}·${R} ${YEL}${B}fast${R}"
else
    line2="$line2 ${D}· fast off${R}"
fi

if [ -n "$pct" ]; then
    p=${pct%%.*}
    if   [ "$p" -ge 90 ]; then c=$RED
    elif [ "$p" -ge 70 ]; then c=$YEL
    else                       c=$GRN
    fi
    line2="$line2 ${D}·${R} ctx ${c}${p}%${R}"
else
    line2="$line2 ${D}· ctx --${R}"
fi
printf '%s\n' "$line2"

pace_color() {
    local used=$1 reset=$2 window=$3 unit=$4
    awk -v used="$used" -v reset="$reset" -v now="$(date +%s)" \
        -v w="$window" -v u="$unit" '
        BEGIN {
            elapsed = w - (reset - now) / u
            if (elapsed < 0) elapsed = 0
            if (used > (100 / w) * elapsed)             printf "\033[31m"
            else if (used > (100 / w) * (elapsed - 0.5)) printf "\033[33m"
            else                                         printf "\033[32m"
        }'
}

remaining() {
    awk -v reset="$1" -v now="$(date +%s)" '
        BEGIN {
            s = reset - now
            if (s < 0) s = 0
            d = int(s / 86400); h = int(s % 86400 / 3600); m = int(s % 3600 / 60)
            if (d > 0) printf "%dd%02dh", d, h
            else       printf "%dh%02dm", h, m
        }'
}

bar() {
    local pct=$1 width=10
    awk -v p="$pct" -v w="$width" '
        BEGIN {
            filled = int(p * w / 100 + 0.5)
            if (filled > w) filled = w
            if (filled < 0) filled = 0
            out = ""
            for (i = 0; i < filled; i++) out = out "█"
            for (i = filled; i < w; i++) out = out "░"
            printf "%s", out
        }'
}

window_field() {
    local label=$1 path=$2 window=$3 unit=$4
    local used reset remain c
    used=$(q "$path.used_percentage")
    reset=$(q "$path.resets_at")
    if [ -z "$used" ] || [ -z "$reset" ]; then
        printf '%s' "${D}${label}: --${R}"
        return
    fi
    remain=$(awk -v u="$used" 'BEGIN { r = 100 - u; if (r < 0) r = 0; printf "%d", r }')
    c=$(pace_color "$used" "$reset" "$window" "$unit")
    printf '%s' "${D}${label}:${R} ${c}$(bar "$remain")${R} ${c}${remain}%${R} ${D}($(remaining "$reset"))${R}"
}

# total_input/output_tokens はコンテキストウィンドウ内の現在値であり、セッション累計ではない
fmt_tok() {
    awk -v n="$1" 'BEGIN {
        if (n == "") { print "--"; exit }
        if (n >= 1000) printf "%.1fk", n / 1000
        else            printf "%d", n
    }'
}
in_tok=$(fmt_tok "$(q '.context_window.total_input_tokens')")
out_tok=$(fmt_tok "$(q '.context_window.total_output_tokens')")

printf '%s   %s   %s\n' \
    "$(window_field 5h  .rate_limits.five_hour 5 3600)" \
    "$(window_field 7d  .rate_limits.seven_day 7 86400)" \
    "${D}in${R} ${in_tok} ${D}out${R} ${out_tok}"

# 他セッションの状態 (~/.claude/agent-status/<session_id>.json は claude/agent-status.sh が書く)。
# processing/waiting_input は放置、done は書き込みから 60 秒だけ見せて消す。
# 更新が 15 分止まっているものは異常終了 (kill 等で SessionEnd が発火しなかった) とみなし削除する。
self=$(q '.session_id')
now=$(date +%s)
line4=""
agent_dir="$HOME/.claude/agent-status"
if [ -d "$agent_dir" ]; then
    for f in "$agent_dir"/*.json; do
        [ -e "$f" ] || continue
        sid=$(jq -r '.session_id // empty' "$f" 2>/dev/null)
        [ -n "$sid" ] && [ "$sid" != "$self" ] || continue

        ts=$(jq -r '.updated_at // 0' "$f" 2>/dev/null)
        age=$((now - ${ts:-0}))
        if [ "$age" -gt 900 ] || { [ "$(jq -r '.state // empty' "$f" 2>/dev/null)" = "done" ] && [ "$age" -gt 60 ]; }; then
            rm -f "$f" 2>/dev/null
            continue
        fi

        state=$(jq -r '.state // empty' "$f" 2>/dev/null)
        aname=$(jq -r '.name // "?"' "$f" 2>/dev/null)
        case "$state" in
            processing)    c=$CYN; icon="●" ;;
            waiting_input) c=$YEL; icon="◐" ;;
            done)          c=$GRN; icon="✓" ;;
            error)         c=$RED; icon="✗" ;;
            *)             continue ;;
        esac
        line4="${line4}${line4:+   }${c}${icon}${R} ${aname}"
    done
fi
if [ -n "$line4" ]; then
    printf '%s\n' "$line4"
fi
