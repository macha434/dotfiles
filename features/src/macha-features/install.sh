#!/usr/bin/env bash
# agent の状態を名前付き volume に載せ、必要なら CLI も入れる。ビルド時に root で走る。
set -euo pipefail

USERNAME="${_REMOTE_USER:-vscode}"
HOME_DIR="${_REMOTE_USER_HOME:-/home/$USERNAME}"
STATE=/var/lib/agent-state
SHARE=/usr/local/share/macha-features
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENTS=(claude codex copilot)

for f in claude/statusline-command.sh claude/settings.json claude/keybindings.json \
         codex/config.toml \
         copilot/statusline-command.sh copilot/settings.json; do
    if [ ! -f "$SRC/$f" ]; then
        echo "macha-features: $f が無い。features/sync-assets.sh を先に実行すること" >&2
        exit 1
    fi
done


echo "macha-features: $STATE を用意する (user=$USERNAME)"

install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE"

for name in "${AGENTS[@]}"; do
    install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE/$name"

    # ベースイメージが既に設定を持っているなら volume 側へ移してから貼り替える
    if [ -d "$HOME_DIR/.$name" ] && [ ! -L "$HOME_DIR/.$name" ]; then
        cp -a "$HOME_DIR/.$name/." "$STATE/$name/"
        rm -rf "$HOME_DIR/.$name"
        chown -R "$USERNAME:$USERNAME" "$STATE/$name"
    fi

    ln -sfn "$STATE/$name" "$HOME_DIR/.$name"
    chown -h "$USERNAME:$USERNAME" "$HOME_DIR/.$name"
done

# oauthAccount を含む ~/.claude.json も symlink する (無いと再ログインを求められる)
CLAUDE_JSON="$HOME_DIR/.claude.json"
CLAUDE_JSON_STATE="$STATE/claude/.claude.json"
if [ -f "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ]; then
    cp -a "$CLAUDE_JSON" "$CLAUDE_JSON_STATE"
    rm -f "$CLAUDE_JSON"
    chown "$USERNAME:$USERNAME" "$CLAUDE_JSON_STATE"
fi
ln -sfn "$CLAUDE_JSON_STATE" "$CLAUDE_JSON"
chown -h "$USERNAME:$USERNAME" "$CLAUDE_JSON"

# codex/config.toml の配置はここではやらない (volume 未マウント。ensure-codex.sh 参照)

# ---- jq ------------------------------------------------------------------
# entrypoint.sh のテンプレートマージと statusline に要る
if { [ "${CLAUDE:-false}" = "true" ] || [ "${COPILOT:-false}" = "true" ]; } \
   && ! command -v jq >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        echo "macha-features: jq を入れる"
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends jq
        rm -rf /var/lib/apt/lists/*
    else
        echo "macha-features: jq が無く apt-get も無いので入れられない。settings.json は statusLine しか当たらない" >&2
    fi
fi

# ---- CLI ---------------------------------------------------------------
# root のままだと $HOME が /root になるので remote user で実行する
run_as_user() {
    su - "$USERNAME" -c "$1"
}

if [ "${CLAUDE:-false}" = "true" ]; then
    echo "macha-features: Claude Code CLI を入れる"
    run_as_user 'curl -fsSL https://claude.ai/install.sh | bash'
fi

# curl|bash に直接 </dev/null を付けると動かない (リダイレクトがパイプより優先され、bash が /dev/null を読む)
if [ "${COPILOT:-false}" = "true" ]; then
    echo "macha-features: GitHub Copilot CLI を入れる"
    run_as_user '
        installer=$(mktemp)
        curl -fsSL https://gh.io/copilot-install -o "$installer"
        bash "$installer" </dev/null
        rm -f "$installer"
    '
fi

# Codex はここでは入れない。バイナリが volume 内に入るため、毎起動 entrypoint 側で判定する

# ~/.local/bin は Ubuntu の ~/.profile が拾うが、非ログインシェルでは読まれない
cat > /etc/profile.d/macha-features-path.sh <<'PROFILE'
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
PROFILE
chmod 644 /etc/profile.d/macha-features-path.sh

install -d "$SHARE"
install -m 755 "$SRC/entrypoint.sh"          "$SHARE/entrypoint.sh"
install -m 755 "$SRC/claude/statusline-command.sh" "$SHARE/claude-statusline.sh"
install -m 644 "$SRC/claude/settings.json"    "$SHARE/claude-settings.json"
install -m 644 "$SRC/claude/keybindings.json" "$SHARE/claude-keybindings.json"
install -m 644 "$SRC/codex/config.toml"      "$SHARE/codex-config.toml"
install -m 755 "$SRC/copilot/statusline-command.sh" "$SHARE/copilot-statusline.sh"
install -m 644 "$SRC/copilot/settings.json"  "$SHARE/copilot-settings.json"
install -m 755 "$SRC/ensure-codex.sh"        "$SHARE/ensure-codex.sh"

# _REMOTE_USER も option もビルド時にしか渡らないので、entrypoint 用に焼き込む
{
    printf 'USERNAME=%q\n' "$USERNAME"
    printf 'HOME_DIR=%q\n' "$HOME_DIR"
    printf 'STATE=%q\n'    "$STATE"
    printf 'AGENTS=(%s)\n' "${AGENTS[*]}"
    printf 'CLAUDE=%q\n'   "${CLAUDE:-false}"
    printf 'CODEX=%q\n'    "${CODEX:-false}"
    printf 'COPILOT=%q\n'  "${COPILOT:-false}"
} > "$SHARE/config"
chmod 644 "$SHARE/config"

echo "macha-features: 完了"
