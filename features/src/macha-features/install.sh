#!/usr/bin/env bash
# agent の状態を名前付き volume に載せ、必要なら CLI も入れる。ビルド時に root で走る。
set -euo pipefail

USERNAME="${_REMOTE_USER:-vscode}"
HOME_DIR="${_REMOTE_USER_HOME:-/home/$USERNAME}"
STATE=/var/lib/agent-state
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENTS=(claude codex copilot gh)

# $HOME/.<name> に収まらないものだけここで上書きする (gh auth login の資格情報は ~/.config/gh)
declare -A HOME_REL=(
    [gh]=".config/gh"
)

# shellcheck source=lib/common.sh
. "$SRC/lib/common.sh"
# shellcheck source=lib/volume.sh
. "$SRC/lib/volume.sh"
# shellcheck source=lib/cli-install.sh
. "$SRC/lib/cli-install.sh"

require_assets
setup_state_dir
symlink_agent_dirs
symlink_claude_json
install_herdr_config

ensure_jq
ensure_uv
install_claude_cli
install_copilot_cli
install_herdr_cli
install_graphify_cli
# Codex はここでは入れない。バイナリが volume 内に入るため、毎起動 runtime/ensure-codex.sh 側で判定する
setup_path_profile

install -d "$SHARE"
install -m 755 "$SRC/runtime/entrypoint.sh"    "$SHARE/entrypoint.sh"
install -m 755 "$SRC/runtime/ensure-codex.sh"  "$SHARE/ensure-codex.sh"
install -m 755 "$SRC/runtime/ensure-skills.sh" "$SHARE/ensure-skills.sh"
install -m 755 "$SRC/claude/statusline-command.sh" "$SHARE/claude-statusline.sh"
install -m 755 "$SRC/claude/agent-status.sh"      "$SHARE/claude-agent-status.sh"
install -m 644 "$SRC/claude/settings.json"    "$SHARE/claude-settings.json"
install -m 644 "$SRC/claude/keybindings.json" "$SHARE/claude-keybindings.json"
install -m 644 "$SRC/codex/config.toml"      "$SHARE/codex-config.toml"
install -m 755 "$SRC/copilot/statusline-command.sh" "$SHARE/copilot-statusline.sh"
install -m 644 "$SRC/copilot/settings.json"  "$SHARE/copilot-settings.json"
install -m 644 "$SRC/claude-skills.json"     "$SHARE/claude-skills.json"
install -m 644 "$SRC/codex-skills.json"      "$SHARE/codex-skills.json"
install -m 644 "$SRC/copilot-skills.json"    "$SHARE/copilot-skills.json"

install -d "$SHARE/lib"
install -m 644 "$SRC/lib/common.sh"   "$SHARE/lib/common.sh"
install -m 644 "$SRC/lib/settings.sh" "$SHARE/lib/settings.sh"
install -m 644 "$SRC/lib/skills.sh"   "$SHARE/lib/skills.sh"
install -m 644 "$SRC/lib/graphify.sh" "$SHARE/lib/graphify.sh"

# _REMOTE_USER も option もビルド時にしか渡らないので、runtime 用に焼き込む
{
    printf 'USERNAME=%q\n' "$USERNAME"
    printf 'HOME_DIR=%q\n' "$HOME_DIR"
    printf 'STATE=%q\n'    "$STATE"
    printf 'AGENTS=(%s)\n' "${AGENTS[*]}"
    printf 'CLAUDE=%q\n'         "${CLAUDE:-false}"
    printf 'CODEX=%q\n'          "${CODEX:-false}"
    printf 'COPILOT=%q\n'        "${COPILOT:-false}"
    printf 'HERDR=%q\n'          "${HERDR:-false}"
    printf 'GRAPHIFY=%q\n'       "${GRAPHIFY:-false}"
    printf 'CLAUDE_SKILLS=%q\n'  "${CLAUDESKILLS:-false}"
    printf 'CODEX_SKILLS=%q\n'   "${CODEXSKILLS:-false}"
    printf 'COPILOT_SKILLS=%q\n' "${COPILOTSKILLS:-false}"
} > "$SHARE/config"
chmod 644 "$SHARE/config"

echo "macha-features: 完了"
