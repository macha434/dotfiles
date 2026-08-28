#!/usr/bin/env bash
# agent の状態 (~/.claude, ~/.codex) を名前付き volume に載せる。
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

# option は大文字の環境変数で届く。値は "true" / "false" の文字列。
agents=()
[ "${CLAUDE:-false}" = "true" ] && agents+=(claude)
[ "${CODEX:-false}"  = "true" ] && agents+=(codex)

if [ ${#agents[@]} -eq 0 ]; then
    echo "agent-state: 有効な agent が無いので何もしない"
    exit 0
fi

echo "agent-state: ${agents[*]} を $STATE に載せる (user=$USERNAME)"

install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE"

for name in "${agents[@]}"; do
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

# _REMOTE_USER はビルド時にしか渡らないので、値を焼き込んで entrypoint を生成する。
# entrypoint はコンテナ起動ごとに root で、volume がマウントされた後に走る。
install -d /usr/local/share/agent-state
{
    echo '#!/usr/bin/env bash'
    echo 'set -eu'
    printf 'USERNAME=%q\n' "$USERNAME"
    printf 'STATE=%q\n'    "$STATE"
    printf 'AGENTS=(%s)\n' "${agents[*]}"
    cat <<'INNER'

uid=$(id -u "$USERNAME")
gid=$(id -g "$USERNAME")

# 既に中身のある volume を掴んだ場合、コピーアップは起きない。
# 後から agent を有効化したときのためにサブディレクトリを補う。
for name in "${AGENTS[@]}"; do
    [ -d "$STATE/$name" ] || mkdir -p "$STATE/$name"
done

# 別 uid のイメージが初期化した volume と、直前の行が root で作ったばかりの
# サブディレクトリの両方に備える。$STATE だけを見ると後者を取りこぼす。
# bind mount と違いホスト側に実体が無いので chown して差し支えない。
if [ "$(id -u)" = 0 ]; then
    for dir in "$STATE" "${AGENTS[@]/#/$STATE/}"; do
        [ -d "$dir" ] || continue
        [ "$(stat -c %u "$dir")" = "$uid" ] || chown -R "$uid:$gid" "$dir"
        chmod 700 "$dir"
    done
fi

# 複数 feature の entrypoint は数珠つなぎに呼ばれるので、これを落とすと後続が動かない
exec "$@"
INNER
} > /usr/local/share/agent-state/entrypoint.sh
chmod +x /usr/local/share/agent-state/entrypoint.sh

echo "agent-state: 完了"
