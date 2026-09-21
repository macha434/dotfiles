#!/usr/bin/env bash
# コンテナ起動ごとに root で走る。volume はマウント済み。
set -eu

# shellcheck source=/dev/null
. /usr/local/share/macha-features/lib/paths.sh
# shellcheck source=/dev/null
. "$SHARE/config"
# shellcheck source=/dev/null
. "$SHARE/lib/settings.sh"

uid=$(id -u "$USERNAME")
gid=$(id -g "$USERNAME")

for name in "${AGENTS[@]}"; do
    [ -d "$STATE/$name" ] || mkdir -p "$STATE/$name"
done

if [ "$(id -u)" = 0 ]; then
    for dir in "$STATE" "${AGENTS[@]/#/$STATE/}"; do
        [ -d "$dir" ] || continue
        [ "$(stat -c %u "$dir")" = "$uid" ] || chown -R "$uid:$gid" "$dir"
        chmod 700 "$dir"
    done
fi

if [ "${CLAUDE:-false}" = "true" ]; then
    apply_json_config "$STATE/claude/settings.json" \
                      "$SHARE/claude-settings.json" \
                      "$SHARE/claude-statusline.sh" 1 \
                      "$SHARE/claude-agent-status.sh"
    apply_claude_keybindings
fi

if [ "${COPILOT:-false}" = "true" ]; then
    apply_json_config "$STATE/copilot/settings.json" \
                      "$SHARE/copilot-settings.json" \
                      "$SHARE/copilot-statusline.sh" ""
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
