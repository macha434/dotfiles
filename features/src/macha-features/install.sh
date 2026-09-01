#!/usr/bin/env bash
# agent の状態を名前付き volume に載せ、必要なら CLI も入れる。
#
# ここはイメージのビルド時に root で走る。volume はまだ存在しない。
# このスクリプトが作った $STATE の中身と所有権が、空 volume の初回マウント時に
# そのままコピーアップされる。それがこの feature の肝で、実行時の chown が
# 要らない理由でもある。
#
# volume を $HOME の下ではなく /var/lib に張るのは、mounts の target が静的な
# メタデータでユーザー名を展開できないため。ユーザー依存の部分 (symlink の
# 張り先) だけをここで動的に解決する。
set -euo pipefail

USERNAME="${_REMOTE_USER:-vscode}"
HOME_DIR="${_REMOTE_USER_HOME:-/home/$USERNAME}"
STATE=/var/lib/agent-state
SHARE=/usr/local/share/macha-features
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ~/.claude と ~/.codex は option に関わらず両方用意する。
# option が決めるのは CLI を入れるかどうかと statusline を当てるかどうかだけ。
AGENTS=(claude codex)

# statusline スクリプト・settings.json・keybindings.json は dotfiles 本体 (claude/) が
# 正で、features/sync-assets.sh がここへ複製する。tarball には feature 配下しか入らない
# ため実体のコピーが要る。
for f in statusline-command.sh settings.json keybindings.json; do
    if [ ! -f "$SRC/claude/$f" ]; then
        echo "macha-features: claude/$f が無い。features/sync-assets.sh を先に実行すること" >&2
        exit 1
    fi
done
if [ ! -f "$SRC/codex/config.toml" ]; then
    echo "macha-features: codex/config.toml が無い。features/sync-assets.sh を先に実行すること" >&2
    exit 1
fi


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

# ~/.claude (このループで volume 化した) とは別に、Claude Code は
# oauthAccount を含むグローバル設定を ~/.claude.json という、ホーム直下の
# 別ファイルにも持つ。~/.claude/.credentials.json 自体は上のループで volume
# に乗るが、ログイン判定は oauthAccount の有無も見ているため、この
# ファイルを見落とすとコンテナを作り直すたびに再ログインを求められる
# (実機で確認済み)。ディレクトリと同じ考え方でファイルとして symlink する。
CLAUDE_JSON="$HOME_DIR/.claude.json"
CLAUDE_JSON_STATE="$STATE/claude/.claude.json"
if [ -f "$CLAUDE_JSON" ] && [ ! -L "$CLAUDE_JSON" ]; then
    cp -a "$CLAUDE_JSON" "$CLAUDE_JSON_STATE"
    rm -f "$CLAUDE_JSON"
    chown "$USERNAME:$USERNAME" "$CLAUDE_JSON_STATE"
fi
ln -sfn "$CLAUDE_JSON_STATE" "$CLAUDE_JSON"
chown -h "$USERNAME:$USERNAME" "$CLAUDE_JSON"

# Codex の config.toml は claude/settings.json と違い、volume が空のとき (= 初回)
# だけ置く。settings.json は Claude Code 側が壊さない前提でテンプレートを毎起動
# 上書きできるが、Codex CLI は config.toml の一部 (キーバインドのカスタマイズなど)
# を自分で書き戻す。毎起動上書きするとその変更が消えてしまうため、既にファイルが
# あれば触らない。テンプレートを更新しても既存 volume には届かないので、反映
# したいときは `docker volume rm agent-state` でリセットすること。
CODEX_CONFIG="$STATE/codex/config.toml"
if [ ! -e "$CODEX_CONFIG" ]; then
    install -m 644 "$SRC/codex/config.toml" "$CODEX_CONFIG"
    chown "$USERNAME:$USERNAME" "$CODEX_CONFIG"
fi

# ---- jq ------------------------------------------------------------------
# entrypoint.sh が毎起動 settings.json をテンプレートとマージするのに使う。
# base image が入れている前提を置かず、ここで確実に用意する。無いままだと
# entrypoint 側は statusLine だけの最小構成にフォールバックし、model や
# editorMode などは当たらない。
if [ "${CLAUDE:-false}" = "true" ] && ! command -v jq >/dev/null 2>&1; then
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
# どちらのインストーラも $HOME/.local/ に入れるので、root ではなく
# remote user で走らせないと /root の下に入ってしまう。
run_as_user() {
    su - "$USERNAME" -c "$1"
}

if [ "${CLAUDE:-false}" = "true" ]; then
    echo "macha-features: Claude Code CLI を入れる"
    run_as_user 'curl -fsSL https://claude.ai/install.sh | bash'
fi

# Codex はここで入れない。インストーラがバイナリ本体を ~/.codex/packages/ に置く
# ため、実体が volume の中に入る。ビルド時に入れても中身が volume に届くのは
# コピーアップが起きる初回だけで、2 回目以降のコンテナではランチャが宙を指す。
# 代わりに entrypoint が「volume に無ければ入れる」を毎起動で見る。

# ~/.local/bin は Ubuntu の ~/.profile が拾うが、非ログインシェルでは読まれない
cat > /etc/profile.d/macha-features-path.sh <<'PROFILE'
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac
PROFILE
chmod 644 /etc/profile.d/macha-features-path.sh

# ---- entrypoint と claude の設定テンプレート ----------------------------
# statusline スクリプト・settings.json・keybindings.json は volume の外に置く。
# volume に置くとコピーアップが初回しか起きず、更新が 2 回目以降のコンテナに
# 届かないため。settings.json は entrypoint が毎起動 jq でマージする際の
# テンプレートとして、keybindings.json は symlink 先として使う。
install -d "$SHARE"
install -m 755 "$SRC/entrypoint.sh"          "$SHARE/entrypoint.sh"
install -m 755 "$SRC/claude/statusline-command.sh" "$SHARE/claude-statusline.sh"
install -m 644 "$SRC/claude/settings.json"    "$SHARE/claude-settings.json"
install -m 644 "$SRC/claude/keybindings.json" "$SHARE/claude-keybindings.json"
install -m 755 "$SRC/ensure-codex.sh"        "$SHARE/ensure-codex.sh"

# _REMOTE_USER も option もビルド時にしか渡らないので、entrypoint 用に焼き込む
{
    printf 'USERNAME=%q\n' "$USERNAME"
    printf 'HOME_DIR=%q\n' "$HOME_DIR"
    printf 'STATE=%q\n'    "$STATE"
    printf 'AGENTS=(%s)\n' "${AGENTS[*]}"
    printf 'CLAUDE=%q\n'   "${CLAUDE:-false}"
    printf 'CODEX=%q\n'    "${CODEX:-false}"
} > "$SHARE/config"
chmod 644 "$SHARE/config"

echo "macha-features: 完了"
