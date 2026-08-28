# agent-state

`~/.claude` や `~/.codex` を名前付き Docker volume に載せて、dev container を作り直しても
消えないようにする feature。volume 名を固定しているので、プロジェクトをまたいで同じ状態を
共有する（ログインは 1 回で済む）。

```jsonc
"features": {
    "ghcr.io/macha434/dotfiles/agent-state:1": {
        "claude": true,
        "codex": false
    }
}
```

VS Code のユーザー設定に書けば、以後このマシンで作るすべての dev container に効く。

```jsonc
"dev.containers.defaultFeatures": {
    "ghcr.io/macha434/dotfiles/agent-state:1": { "claude": true }
}
```

## Options

| id | type | default | 説明 |
| --- | --- | --- | --- |
| `claude` | boolean | `true` | `~/.claude` を永続化する |
| `codex` | boolean | `false` | `~/.codex` を永続化する |

## しくみ

```
volume "agent-state"
   └─ mount → /var/lib/agent-state
                ├─ claude/  ←── symlink ── $HOME/.claude
                └─ codex/   ←── symlink ── $HOME/.codex
```

option で `mounts` を出し分けることはできない（`mounts` は静的なメタデータで、option は
install スクリプトに環境変数として届くだけ）。そのため volume は 1 本だけ固定でマウントし、
**どの agent を有効にするかは symlink を張るかどうかで表現する**。

マウント先を `$HOME` の下に置いていないのは、`mounts` の `target` が `_REMOTE_USER_HOME` を
展開できないため。`/home/vscode` を決め打ちすると `remoteUser` が違うイメージで壊れる。
`/var/lib/agent-state` なら誰が使っても同じで、ユーザー依存の symlink だけを
install スクリプトが動的に解決する。

所有権は実行時に直しているのではなく、**空の volume がマウント先の所有権を継承する**性質を
使っている。ビルド時に `/var/lib/agent-state` を remote user 所有で作っておけば、初回
マウント時にその所有権ごと volume にコピーアップされるので、sudo 無しで書ける状態から
始まる。

## 運用

- **リセットしたいとき**: `docker volume rm agent-state`。所有権の継承は volume が空の
  ときにしか起きないので、feature を直しても既存 volume は直らない
- **同時起動**: 複数コンテナを並行して立てると同じ状態に書く。1 台で複数セッションを
  開くのと同じ状況
- **`docker volume prune` では消えない**: 名前付き volume は `-a` を付けたときだけ対象

詳細な設計判断と検証手順は [docs/agent-state-feature-plan.md](../../../docs/agent-state-feature-plan.md) にある。
