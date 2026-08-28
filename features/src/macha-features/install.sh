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

# statusline スクリプトは dotfiles 本体 (claude/) が正で、features/sync-assets.sh が
# ここへ複製する。tarball には feature 配下しか入らないため実体のコピーが要る。
if [ ! -f "$SRC/claude/statusline-command.sh" ]; then
    echo "macha-features: claude/statusline-command.sh が無い。features/sync-assets.sh を先に実行すること" >&2
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

# ---- entrypoint と statusline ------------------------------------------
# statusline スクリプトは volume の外に置く。volume に置くとコピーアップが
# 初回しか起きず、更新が 2 回目以降のコンテナに届かないため。
install -d "$SHARE"
install -m 755 "$SRC/entrypoint.sh"          "$SHARE/entrypoint.sh"
install -m 755 "$SRC/claude/statusline-command.sh" "$SHARE/claude-statusline.sh"
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
