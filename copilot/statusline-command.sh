#!/usr/bin/env bash
# GitHub Copilot CLI のステータスライン。stdin にセッション情報の JSON が渡る。
# claude/statusline-command.sh と対になる内容にしている。
#
#   1 行目  モデル ID / パーミッション / コンテキスト使用率
#   2 行目  消費 (AI クレジット・premium リクエスト)
#
# Claude 版が 3 行なのに対しこちらが 2 行なのは、渡ってくる JSON に対応する
# フィールドが無いため。Claude 版との対応は次のとおり。
#   1 行目 (vim モード) … Copilot の JSON に vim の状態が入らないので落とした。
#                         editorMode: "vim" 自体は効いているが表示はできない。
#   2 行目 … model.id は同名で入る。effort と fast mode は入らないので落とし、
#            代わりに allow_all_enabled (全許可モードかどうか) を出している。
#   3 行目 … レート制限の窓 (5 時間 / 7 日) に相当するものが無い。Copilot は
#            残量ではなく消費の累計 (ai_used / premium リクエスト) を渡してくる
#            ので、上限との比較ができない。色分けもできないため、値をそのまま出す。
#
# 存在しないフィールドは Claude 版と同じくすべて空文字にフォールバックする。
#   current_context_used_percentage … セッション初期は null
#   ai_used / cost … 最初の API 応答があるまで 0 か欠ける
set -uo pipefail

input=$(cat)
q() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
BLU=$'\033[34m'

# ---- 1 行目: モデルと消費 -----------------------------------------------
model=$(q '.model.id')
allow=$(q '.allow_all_enabled')
# current_context_used_percentage が今のコンテキストの埋まり具合で、Claude の
# context_window.used_percentage に相当する。used_percentage はセッション累計
# なので意味が違うが、前者が来ない間の代わりには使える。
pct=$(q '.context_window.current_context_used_percentage')
[ -n "$pct" ] || pct=$(q '.context_window.used_percentage')

line1="${BLU}${model:-?}${R}"

# 全許可は落とすと危ないほうへ倒れるので、Claude の fast mode と逆に
# 有効なときを赤で目立たせる。
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

# ---- 2 行目: 消費 --------------------------------------------------------
# 上限が渡ってこないのでペース判定ができない。ラベルだけ薄くして値を並べる。
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
