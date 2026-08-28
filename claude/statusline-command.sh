#!/usr/bin/env bash
# Claude Code のステータスライン。stdin にセッション情報の JSON が渡る。
#
#   1 行目  vim モード
#   2 行目  モデル ID / effort / fast mode / コンテキスト使用率
#   3 行目  レート制限 (5 時間窓・7 日窓)
#
# レート制限の色は「経過ぶんの線形ペース」との比較で決める。5 時間窓なら 1 時間あたり
# 20% が等速で、2 時間経過なら 40% を超えて赤、30% (0.5 時間ぶん手前) を超えて黄色。
# 7 日窓も同じ考え方を日単位で適用する。
#
# 存在しないフィールドが多いので、すべて空文字にフォールバックして組み立てる。
#   vim         … vim モードが無効なら丸ごと欠ける
#   effort      … reasoning effort 非対応モデルでは欠ける
#   rate_limits … Pro / Max で最初の API 応答があるまで欠ける
#   context_window.used_percentage … セッション初期は null
set -uo pipefail

input=$(cat)
q() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'

# ---- 1 行目: vim モード -------------------------------------------------
vim=$(q '.vim.mode')
case "$vim" in
    NORMAL)        printf '%s\n' "${GRN}${B}NORMAL${R}" ;;
    INSERT)        printf '%s\n' "${CYN}${B}INSERT${R}" ;;
    VISUAL*)       printf '%s\n' "${MAG}${B}${vim}${R}" ;;
    "")            printf '%s\n' "${D}(vim off)${R}" ;;
    *)             printf '%s\n' "${B}${vim}${R}" ;;
esac

# ---- 2 行目: モデルと消費 -----------------------------------------------
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

# ---- 3 行目: レート制限 -------------------------------------------------
# 経過ぶんの線形ペースを超えていれば赤、0.5 単位ぶん手前なら黄色、それ以下は緑。
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

# 残り時間を 2h13m / 4d03h の形にする
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

window_field() {
    local label=$1 path=$2 window=$3 unit=$4
    local used reset
    used=$(q "$path.used_percentage")
    reset=$(q "$path.resets_at")
    if [ -z "$used" ] || [ -z "$reset" ]; then
        printf '%s' "${D}${label} --${R}"
        return
    fi
    printf '%s' "${D}${label}${R} $(pace_color "$used" "$reset" "$window" "$unit")${used%%.*}%${R} ${D}($(remaining "$reset"))${R}"
}

printf '%s   %s\n' \
    "$(window_field 5h  .rate_limits.five_hour 5 3600)" \
    "$(window_field 7d  .rate_limits.seven_day 7 86400)"
