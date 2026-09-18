# root のままだと $HOME が /root になるので remote user で実行する
run_as_user() {
    su - "$USERNAME" -c "$1"
}

# $1: インストーラの URL  $2: 実行するシェル (bash/sh)
curl_pipe_install() {
    run_as_user "curl -fsSL '$1' | $2"
}

# 対象 option のいずれかが有効なときだけ jq を入れる
ensure_jq() {
    { [ "${CLAUDE:-false}" = "true" ] || [ "${COPILOT:-false}" = "true" ] \
      || [ "${CLAUDESKILLS:-false}" = "true" ] || [ "${CODEXSKILLS:-false}" = "true" ] \
      || [ "${COPILOTSKILLS:-false}" = "true" ]; } || return 0
    command -v jq >/dev/null 2>&1 && return 0

    if command -v apt-get >/dev/null 2>&1; then
        echo "macha-features: jq を入れる"
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends jq
        rm -rf /var/lib/apt/lists/*
    else
        echo "macha-features: jq が無く apt-get も無いので入れられない。settings.json は statusLine しか当たらない (skillのインストールも動かない)" >&2
    fi
}

install_claude_cli() {
    [ "${CLAUDE:-false}" = "true" ] || return 0
    echo "macha-features: Claude Code CLI を入れる"
    curl_pipe_install https://claude.ai/install.sh bash
}

# インストーラを一時ファイルに落としてから実行する (curl|bash </dev/null はパイプと競合して失敗する)
install_copilot_cli() {
    [ "${COPILOT:-false}" = "true" ] || return 0
    echo "macha-features: GitHub Copilot CLI を入れる"
    run_as_user '
        installer=$(mktemp)
        curl -fsSL https://gh.io/copilot-install -o "$installer"
        bash "$installer" </dev/null
        rm -f "$installer"
    '
}

install_herdr_cli() {
    [ "${HERDR:-false}" = "true" ] || return 0
    echo "macha-features: herdr を入れる"
    curl_pipe_install https://herdr.dev/install.sh sh
}

# graphify (PyPI: graphifyy) が要る uv を入れる。$HOME/.local/bin に入るので volume の外
ensure_uv() {
    [ "${GRAPHIFY:-false}" = "true" ] || return 0
    run_as_user 'command -v uv' >/dev/null 2>&1 && return 0
    echo "macha-features: uv を入れる"
    curl_pipe_install https://astral.sh/uv/install.sh sh
}

# CLI 本体だけをここで入れる。skill の登録 (~/.claude/skills 等、volume の中) は
# postCreate の ensure-skills.sh 側 (lib/graphify.sh) で行う
install_graphify_cli() {
    [ "${GRAPHIFY:-false}" = "true" ] || return 0
    echo "macha-features: Graphify を入れる"
    run_as_user 'export PATH="$HOME/.local/bin:$PATH"; uv tool install graphifyy'
}

# ~/.local/bin を PATH に足す (非ログインシェルでは ~/.profile が読まれないため)
setup_path_profile() {
    cat > /etc/profile.d/macha-features-path.sh <<'PROFILE'
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
PROFILE
    chmod 644 /etc/profile.d/macha-features-path.sh
}
