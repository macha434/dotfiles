# graphify install は ~/.claude/skills・~/.codex・~/.copilot (いずれも volume の中) に
# 書き込むため、CLI 本体 (install.sh, ビルド時) とは別に postCreate (ensure-skills.sh) で行う。
# ネットワークアクセスは不要 (ファイル配置のみ)。上書きが通常の動作なので、コンテナ作成の
# たびに毎回実行してよい (冪等)。

install_graphify_skill() {
    local platform=$1
    command -v graphify >/dev/null 2>&1 || { echo "macha-features: graphify CLI が無いので $platform 向け登録をスキップ" >&2; return 0; }

    echo "macha-features: graphify を $platform 向けに登録する"
    graphify install --platform "$platform" </dev/null \
        || echo "macha-features: graphify ($platform) の登録に失敗した" >&2
}

install_graphify_skills() {
    # set -eu 下では "[ cond ] && cmd" は cond が偽のとき非ゼロで終わり、
    # if を挟まない単独の文だとそこでスクリプトごと落ちる
    if [ "${CLAUDE:-false}" = "true" ]; then
        install_graphify_skill claude
    fi
    if [ "${CODEX:-false}" = "true" ]; then
        install_graphify_skill codex
    fi
    if [ "${COPILOT:-false}" = "true" ]; then
        install_graphify_skill copilot
    fi
}
