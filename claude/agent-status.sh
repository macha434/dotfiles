#!/usr/bin/env bash
# Claude Code の hook から呼ばれ、このセッションの状態を他セッションから見える
# ~/.claude/agent-status/<session_id>.json に書く。読み出し側は statusline-command.sh。
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
name=$(q '.session_name')
[ -n "$name" ] || name=$(basename "${cwd:-unknown}")
file="$dir/$session_id.json"

write() {
    local state=$1
    jq -n --arg sid "$session_id" --arg name "$name" --arg cwd "$cwd" \
          --arg state "$state" --argjson ts "$(date +%s)" \
          '{session_id: $sid, name: $name, cwd: $cwd, state: $state, updated_at: $ts}' \
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
