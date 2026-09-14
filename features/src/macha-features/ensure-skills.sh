#!/usr/bin/env bash
# postCreateCommand としてコンテナ作成後に remote user で走る (ensure-codex.sh の後)。
# claude-skills.json / codex-skills.json に載っている名前だけを、対応する
# CLI のプラグインとして冪等に入れる。個々のプラグインは常に macha434/<name>
# リポジトリ・macha434-plugins マーケットプレースという同じ命名規則に従う。
set -eu

SHARE=/usr/local/share/macha-features
# shellcheck source=/dev/null
. "$SHARE/config"

# claude/codex は ~/.local/bin に入るが、postCreateCommand がログインシェル
# 経由とは限らないので PATH に明示で足す
export PATH="$HOME/.local/bin:$PATH"

MARKETPLACE="macha434-plugins"

skill_enabled() {
    # $1: カタログ (JSON配列) のパス  $2: 探す名前
    local catalog=$1 name=$2
    [ -f "$catalog" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e --arg n "$name" 'any(.[]; . == $n)' "$catalog" >/dev/null 2>&1
}

install_claude_skill() {
    local name=$1
    command -v claude >/dev/null 2>&1 || { echo "macha-features: claude CLI が無いので $name をスキップ" >&2; return 0; }
    command -v jq >/dev/null 2>&1 || { echo "macha-features: jq が無いので $name をスキップ" >&2; return 0; }

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
    command -v jq >/dev/null 2>&1 || { echo "macha-features: jq が無いので $name をスキップ" >&2; return 0; }

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

if [ "${CLAUDE:-false}" = "true" ] && [ "${HAIKU_SHUNT:-false}" = "true" ]; then
    if skill_enabled "$SHARE/claude-skills.json" "haiku-shunt"; then
        install_claude_skill "haiku-shunt"
    fi
fi

if [ "${CODEX:-false}" = "true" ] && [ "${LUNA_SHUNT:-false}" = "true" ]; then
    if skill_enabled "$SHARE/codex-skills.json" "luna-shunt"; then
        install_codex_skill "luna-shunt"
    fi
fi
