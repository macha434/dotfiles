#!/usr/bin/env bash
# Claude Code の hook から呼ばれ、このセッションの状態を他セッションから見える
# ~/.claude/agent-status/<session_id>.json に書く。読み出し側は statusline-command.sh。
# name は呼ばれるたびに作り直さず、より情報量の多い名前が手に入ったときだけ
# 上書きする(name_rank: 1=cwd, 2=最初の指示文の冒頭, 3=手動/自動タイトル)。
# rank3 は hooks からは分からない(session_name は statusLine の JSON にしか来ない)ので
# statusline-command.sh 側が書く。
# 表示内容・色分けロジックは features/src/macha-features/README.md 参照。
set -uo pipefail

dir="$HOME/.claude/agent-status"
mkdir -p "$dir" 2>/dev/null || exit 0

input=$(cat)
q() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

session_id=$(q '.session_id')
[ -n "$session_id" ] || exit 0

event=$(q '.hook_event_name')
cwd=$(q '.cwd')
transcript_path=$(q '.transcript_path')
file="$dir/$session_id.json"

cwd_name() {
    case "$cwd" in
        */.claude/worktrees/*)
            printf '%s/%s' "$(basename "${cwd%/.claude/worktrees/*}")" "$(basename "$cwd")"
            ;;
        *)
            basename "${cwd:-unknown}"
            ;;
    esac
}

# セッション最初のユーザーメッセージ冒頭(サブエージェントの会話は除く)
first_message() {
    [ -n "$transcript_path" ] && [ -f "$transcript_path" ] || return 1
    jq -rs '
        map(select(.type == "user" and .isSidechain == false and (.message.content | type) == "string"))
        | first.message.content // empty
    ' "$transcript_path" 2>/dev/null | tr '\n\r\t' '   ' | sed -E 's/ +/ /g; s/^ //; s/ $//'
}

write() {
    local state=$1
    local name="" rank=0
    if [ -f "$file" ]; then
        name=$(jq -r '.name // empty' "$file" 2>/dev/null)
        rank=$(jq -r '.name_rank // 0' "$file" 2>/dev/null)
    fi
    rank=${rank:-0}

    if [ "$rank" -lt 2 ]; then
        local fm
        fm=$(first_message)
        if [ -n "$fm" ]; then
            name="${fm:0:24}"
            rank=2
        fi
    fi

    if [ "$rank" -lt 1 ]; then
        name=$(cwd_name)
        rank=1
    fi

    jq -n --arg sid "$session_id" --arg name "$name" --argjson rank "$rank" --arg cwd "$cwd" \
          --arg state "$state" --argjson ts "$(date +%s)" \
          '{session_id: $sid, name: $name, name_rank: $rank, cwd: $cwd, state: $state, updated_at: $ts}' \
        > "$file" 2>/dev/null
}

case "$event" in
    SessionStart)
        write waiting_input
        ;;
    UserPromptSubmit)
        write processing
        ;;
    PostToolUse|PostToolUseFailure)
        # 長いツール呼び出しの合間も processing のまま更新時刻だけ進める
        write processing
        ;;
    Stop)
        write waiting_input
        ;;
    StopFailure)
        write error
        ;;
    Notification)
        case "$(q '.notification_type')" in
            permission_prompt|idle_prompt|agent_needs_input)
                write waiting_input
                ;;
        esac
        ;;
    SessionEnd)
        write done
        ;;
esac

exit 0
