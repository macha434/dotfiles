#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る (ensure-codex.sh の後)。
# claudeSkills/codexSkills/copilotSkills が true なら、claude-skills.json /
# codex-skills.json / copilot-skills.json に載っている名前を全部、対応する
# CLI のプラグインとして冪等に入れる。カタログにエントリを足すだけで有効に
# なるので、この option 自体は変えない。個々のプラグインは常に
# macha434/<name> リポジトリ・macha434-plugins マーケットプレースという
# 同じ命名規則に従う。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

# claude/codex は ~/.local/bin に入るが、postCreateCommand がログインシェル
# 経由とは限らないので PATH に明示で足す
export PATH="$HOME/.local/bin:$PATH"

MARKETPLACE="macha434-plugins"

catalog_names() {
    # $1: カタログ (JSON配列) のパス
    local catalog=$1
    [ -f "$catalog" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '.[]' "$catalog" 2>/dev/null
}

install_claude_skill() {
    local name=$1
    command -v claude >/dev/null 2>&1 || { echo "macha-features: claude CLI が無いので $name をスキップ" >&2; return 0; }

    if ! claude plugin marketplace list --json 2>/dev/null | jq -e --arg m "$MARKETPLACE" 'any(.[]; .name == $m)' >/dev/null 2>&1; then
        echo "macha-features: claude marketplace $MARKETPLACE を追加する"
        claude plugin marketplace add "macha434/$name" || echo "macha-features: $MARKETPLACE の追加に失敗した" >&2
    fi

    if claude plugin list --json 2>/dev/null | jq -e --arg id "$name@$MARKETPLACE" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
        return 0
    fi

    echo "macha-features: claude plugin $name を入れる"
    claude plugin install "$name@$MARKETPLACE" -y || echo "macha-features: $name のインストールに失敗した" >&2
}

install_codex_skill() {
    local name=$1
    command -v codex >/dev/null 2>&1 || { echo "macha-features: codex CLI が無いので $name をスキップ" >&2; return 0; }

    if ! codex plugin marketplace list --json 2>/dev/null | jq -e --arg m "$MARKETPLACE" 'any(.marketplaces[]?; .name == $m)' >/dev/null 2>&1; then
        echo "macha-features: codex marketplace $MARKETPLACE を追加する"
        codex plugin marketplace add "macha434/$name" || echo "macha-features: $MARKETPLACE の追加に失敗した" >&2
    fi

    if codex plugin list --json 2>/dev/null | jq -e --arg id "$name@$MARKETPLACE" 'any(.installed[]?; .pluginId == $id)' >/dev/null 2>&1; then
        return 0
    fi

    echo "macha-features: codex plugin $name を入れる"
    codex plugin add "$name@$MARKETPLACE" || echo "macha-features: $name のインストールに失敗した" >&2
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
    local name=$1
    command -v copilot >/dev/null 2>&1 || { echo "macha-features: copilot CLI が無いので $name をスキップ" >&2; return 0; }

    local installed_dir="$HOME/.copilot/installed-plugins/$MARKETPLACE/$name"

    if ! copilot plugin marketplace list 2>/dev/null | grep -qF "$MARKETPLACE "; then
        echo "macha-features: copilot marketplace $MARKETPLACE を追加する"
        copilot plugin marketplace add "macha434/$name" || echo "macha-features: $MARKETPLACE の追加に失敗した" >&2
    fi

    [ -d "$installed_dir" ] && return 0

    echo "macha-features: copilot plugin $name を入れる"
    copilot plugin install "$name@$MARKETPLACE" || echo "macha-features: $name のインストールに失敗した" >&2
}

if [ "${CLAUDE:-false}" = "true" ] && [ "${CLAUDE_SKILLS:-false}" = "true" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] && install_claude_skill "$name"
    done < <(catalog_names "$SHARE/claude-skills.json")
fi

if [ "${CODEX:-false}" = "true" ] && [ "${CODEX_SKILLS:-false}" = "true" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] && install_codex_skill "$name"
    done < <(catalog_names "$SHARE/codex-skills.json")
fi

if [ "${COPILOT:-false}" = "true" ] && [ "${COPILOT_SKILLS:-false}" = "true" ]; then
    while IFS= read -r name; do
        [ -n "$name" ] && install_copilot_skill "$name"
    done < <(catalog_names "$SHARE/copilot-skills.json")
fi
