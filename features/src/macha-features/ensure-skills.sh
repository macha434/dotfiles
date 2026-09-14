#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る (ensure-codex.sh の後)。
# claudeSkills/codexSkills/copilotSkills が true なら、claude-skills.json /
# codex-skills.json / copilot-skills.json に載っているエントリを全部、対応
# する CLI のプラグインとして冪等に入れる。カタログにエントリを足すだけで
# 有効になるので、この option 自体は変えない。
#
# カタログの各エントリは {"name", "repo", "marketplace"} を持つ。特定の
# リポジトリ命名規則には依存しないので、自分以外が作ったプラグインも
# 同じカタログに並べられる。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

# claude/codex は ~/.local/bin に入るが、postCreateCommand がログインシェル
# 経由とは限らないので PATH に明示で足す
export PATH="$HOME/.local/bin:$PATH"

catalog_entries() {
    # $1: カタログ (JSON配列) のパス。1行 "name<TAB>repo<TAB>marketplace" で出す
    local catalog=$1
    [ -f "$catalog" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.[] | [.name, .repo, .marketplace] | @tsv' "$catalog" 2>/dev/null
}

install_claude_skill() {
    local name=$1 repo=$2 marketplace=$3
    command -v claude >/dev/null 2>&1 || { echo "macha-features: claude CLI が無いので $name をスキップ" >&2; return 0; }

    if ! claude plugin marketplace list --json 2>/dev/null | jq -e --arg m "$marketplace" 'any(.[]; .name == $m)' >/dev/null 2>&1; then
        echo "macha-features: claude marketplace $marketplace ($repo) を追加する"
        claude plugin marketplace add "$repo" || echo "macha-features: $marketplace の追加に失敗した" >&2
    fi

    if claude plugin list --json 2>/dev/null | jq -e --arg id "$name@$marketplace" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
        return 0
    fi

    echo "macha-features: claude plugin $name を入れる"
    claude plugin install "$name@$marketplace" -y || echo "macha-features: $name のインストールに失敗した" >&2
}

install_codex_skill() {
    local name=$1 repo=$2 marketplace=$3
    command -v codex >/dev/null 2>&1 || { echo "macha-features: codex CLI が無いので $name をスキップ" >&2; return 0; }

    if ! codex plugin marketplace list --json 2>/dev/null | jq -e --arg m "$marketplace" 'any(.marketplaces[]?; .name == $m)' >/dev/null 2>&1; then
        echo "macha-features: codex marketplace $marketplace ($repo) を追加する"
        codex plugin marketplace add "$repo" || echo "macha-features: $marketplace の追加に失敗した" >&2
    fi

    if codex plugin list --json 2>/dev/null | jq -e --arg id "$name@$marketplace" 'any(.installed[]?; .pluginId == $id)' >/dev/null 2>&1; then
        return 0
    fi

    echo "macha-features: codex plugin $name を入れる"
    codex plugin add "$name@$marketplace" || echo "macha-features: $name のインストールに失敗した" >&2
}

install_copilot_skill() {
    # copilot plugin list / marketplace list には --json が無いため、CLI の
    # テキスト出力ではなく実際のインストール先ディレクトリで冪等性を見る
    # (ensure-codex.sh が codex バイナリの実体で見ているのと同じ考え方)。
    # 実機で確認済み: GitHub 由来のインストールは
    # ~/.copilot/installed-plugins/<marketplace>/<name> に実体ができる。
    #
    # 注意: Copilot の marketplace.json は Claude/Codex とスキーマが違う
    # (owner がオブジェクト必須、plugins[].source が相対パスの文字列直書き)。
    # copilot-skills.json にエントリを足すなら、その対象リポジトリは
    # Copilot 向けの marketplace.json を別途用意する必要がある。
    local name=$1 repo=$2 marketplace=$3
    command -v copilot >/dev/null 2>&1 || { echo "macha-features: copilot CLI が無いので $name をスキップ" >&2; return 0; }

    local installed_dir="$HOME/.copilot/installed-plugins/$marketplace/$name"

    if ! copilot plugin marketplace list 2>/dev/null | grep -qF "$marketplace "; then
        echo "macha-features: copilot marketplace $marketplace ($repo) を追加する"
        copilot plugin marketplace add "$repo" || echo "macha-features: $marketplace の追加に失敗した" >&2
    fi

    [ -d "$installed_dir" ] && return 0

    echo "macha-features: copilot plugin $name を入れる"
    copilot plugin install "$name@$marketplace" || echo "macha-features: $name のインストールに失敗した" >&2
}

install_all() {
    # $1: カタログのパス  $2: install_*_skill 関数名
    local catalog=$1 installer=$2
    local name repo marketplace
    while IFS=$'\t' read -r name repo marketplace; do
        [ -n "$name" ] || continue
        "$installer" "$name" "$repo" "$marketplace"
    done < <(catalog_entries "$catalog")
}

if [ "${CLAUDE:-false}" = "true" ] && [ "${CLAUDE_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/claude-skills.json" install_claude_skill
fi

if [ "${CODEX:-false}" = "true" ] && [ "${CODEX_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/codex-skills.json" install_codex_skill
fi

if [ "${COPILOT:-false}" = "true" ] && [ "${COPILOT_SKILLS:-false}" = "true" ]; then
    install_all "$SHARE/copilot-skills.json" install_copilot_skill
fi
