# 必須アセットの存在を確認する
require_assets() {
    local f
    for f in claude/statusline-command.sh claude/settings.json claude/keybindings.json \
             codex/config.toml \
             copilot/statusline-command.sh copilot/settings.json \
             herdr/config.toml \
             claude-skills.json codex-skills.json copilot-skills.json; do
        if [ ! -f "$SRC/$f" ]; then
            echo "macha-features: $f が無い。features/sync-assets.sh を先に実行すること" >&2
            exit 1
        fi
    done
}

# $STATE ディレクトリを remote user 所有で用意する
setup_state_dir() {
    echo "macha-features: $STATE を用意する (user=$USERNAME)"
    install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE"
}

# AGENTS の各ディレクトリを $STATE 配下に作り、$HOME からの symlink にする
symlink_agent_dirs() {
    local name rel home_path parent
    for name in "${AGENTS[@]}"; do
        install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE/$name"

        rel="${HOME_REL[$name]:-.$name}"
        home_path="$HOME_DIR/$rel"
        parent="$(dirname "$home_path")"
        [ -d "$parent" ] || install -d -m 755 -o "$USERNAME" -g "$USERNAME" "$parent"

        if [ -d "$home_path" ] && [ ! -L "$home_path" ]; then
            cp -a "$home_path/." "$STATE/$name/"
            rm -rf "$home_path"
            chown -R "$USERNAME:$USERNAME" "$STATE/$name"
        fi

        ln -sfn "$STATE/$name" "$home_path"
        chown -h "$USERNAME:$USERNAME" "$home_path"
    done
}

# ~/.claude.json を $STATE/claude/.claude.json への symlink にする
symlink_claude_json() {
    local claude_json="$HOME_DIR/.claude.json"
    local claude_json_state="$STATE/claude/.claude.json"

    if [ -f "$claude_json" ] && [ ! -L "$claude_json" ]; then
        cp -a "$claude_json" "$claude_json_state"
        rm -f "$claude_json"
        chown "$USERNAME:$USERNAME" "$claude_json_state"
    fi
    ln -sfn "$claude_json_state" "$claude_json"
    chown -h "$USERNAME:$USERNAME" "$claude_json"
}

# herdr の既定 config.toml を配置する
install_herdr_config() {
    [ "${HERDR:-false}" = "true" ] || return 0

    install -d -o "$USERNAME" -g "$USERNAME" "$HOME_DIR/.config/herdr"
    install -m 644 -o "$USERNAME" -g "$USERNAME" \
            "$SRC/herdr/config.toml" "$HOME_DIR/.config/herdr/config.toml"
}
