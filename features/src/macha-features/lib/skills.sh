# $1: カタログ (JSON配列) のパス。1行 "name<TAB>repo<TAB>marketplace" で出す
catalog_entries() {
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

# copilot は plugin list/marketplace list が --json 非対応のため、実際の
# インストール先ディレクトリの有無で冪等性を判定する
install_copilot_skill() {
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

# $1: カタログのパス  $2: install_*_skill 関数名
install_all() {
    local catalog=$1 installer=$2
    local name repo marketplace
    while IFS=$'\t' read -r name repo marketplace; do
        [ -n "$name" ] || continue
        "$installer" "$name" "$repo" "$marketplace"
    done < <(catalog_entries "$catalog")
}
