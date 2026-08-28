# macha-features

`~/.claude` と `~/.codex` を名前付き Docker volume に載せて、dev container を作り直しても
消えないようにする。volume 名を固定しているので、プロジェクトをまたいで同じ状態を共有する
（ログインは 1 回で済む）。オプションで agent の CLI 導入とステータスラインの適用も行う。

```jsonc
"features": {
    "ghcr.io/macha434/dotfiles/macha-features:0.2": {
        "claude": true,
        "codex": false
    }
}
```

VS Code のユーザー設定に書けば、以後このマシンで作るすべての dev container に効く。

```jsonc
"dev.containers.defaultFeatures": {
    "ghcr.io/macha434/dotfiles/macha-features:0.2": { "claude": true }
}
```

## Options

| id | type | default | 説明 |
| --- | --- | --- | --- |
| `claude` | boolean | `true` | Claude Code CLI を入れ、ステータスラインを当てる |
| `codex` | boolean | `false` | Codex CLI を入れる |

**永続化はオプションに関わらず常に行う。** `~/.claude` と `~/.codex` はどちらの値でも
volume に載る。オプションが決めるのは CLI を入れるかどうかだけ。

## しくみ

```
volume "agent-state"
   └─ mount → /var/lib/agent-state
                ├─ claude/  ←── symlink ── $HOME/.claude
                └─ codex/   ←── symlink ── $HOME/.codex
```

マウント先を `$HOME` の下に置いていないのは、`mounts` の `target` が `_REMOTE_USER_HOME` を
展開できないため。`/home/vscode` を決め打ちすると `remoteUser` が違うイメージで壊れる。

所有権は実行時に直しているのではなく、**空の volume がマウント先の所有権を継承する**性質を
使っている。ビルド時に `/var/lib/agent-state` を remote user 所有で作っておけば、初回
マウント時にその所有権ごと volume にコピーアップされるので、sudo 無しで書ける状態から始まる。

## 3 つの実行タイミング

やることによって走る場所が違う。どれも理由がある。

| いつ | 何を | なぜそこか |
| --- | --- | --- |
| **ビルド時** `install.sh` (root) | volume のマウント先を用意、symlink、Claude Code CLI、statusline スクリプトの配置 | コピーアップに乗せるにはビルド時でないといけない。Claude Code は `~/.local/` に入る（volume の外）のでイメージに焼ける |
| **起動ごと** `entrypoint.sh` (root) | 所有権の補正、`statusLine` 設定のマージ | `settings.json` は volume の中。ビルド時に書くとコピーアップが起きる初回にしか届かない |
| **作成後** `ensure-codex.sh` (remote user) | Codex CLI | 下記 |

### Codex だけ扱いが違う理由

Codex のインストーラは**バイナリ本体を `~/.codex/packages/` に置く**。つまり実体が volume の
中に入る。ビルド時に入れてもコピーアップが起きる初回にしか届かず、2 回目以降のコンテナでは
`~/.local/bin/codex` が宙を指す。

かといって entrypoint でやるとネットワーク越しのダウンロードがコンテナ起動をブロックする。
そこで `postCreateCommand` に置き、**volume に無いときだけ**入れる。バイナリごと volume に
残るので、ダウンロードは実質初回だけ。実測で 1 回目 30 秒、2 回目 3 秒。

インストーラが張るランチャ `~/.local/bin/codex` はイメージ側にあってコンテナを作り直すと
消えるので、インストールを飛ばす場合でも毎回張り直す。

## ステータスライン

スクリプトの正は**リポジトリルートの [`claude/statusline-command.sh`](../../../claude/) 側**で、
dotfiles として `install.sh` がホストの `~/.claude/` にも配置する。feature 用のコピーは
[`features/sync-assets.sh`](../../sync-assets.sh) が
[`features/assets.tsv`](../../assets.tsv) の対応表に従って生成する（gitignore 済み）。

feature の tarball には feature ディレクトリ配下しか入らず、しかも packaging は symlink を
symlink のまま tar に入れる。リポジトリ内 symlink で共有すると公開された feature が宙を指す
リンクを抱えるので、実体のコピーが要る。同期を忘れるとビルド時に落ちる。

そのコピーを `/usr/local/share/macha-features/claude-statusline.sh` に配置し、
`~/.claude/settings.json` の `statusLine` がそこを指すようにする。

スクリプト本体を volume の外に置いているのが要点。volume に置くと更新が 2 回目以降の
コンテナに届かない。イメージ側なら rebuild のたびに最新になり、settings.json 側は不変な
パスを指すだけなので陳腐化しない。

設定は `jq` で `statusLine` キーだけマージする。コンテナ内で自分が足した他の設定は壊れない。
`jq` が無い環境では、`settings.json` が存在しないときだけ書く。

表示を変えたいときは `claude/statusline-command.sh` を編集する。ホスト側は
`./install.sh claude` で即反映される。**コンテナ側に反映するには `version` を上げること。**
複製元を変えると CI は起動するが、version が同じままだと publish はスキップされる。

Codex には Claude Code の `statusLine` に相当する仕組みが見当たらないため、Codex 側の
ステータスライン設定は行っていない。

## 運用

- **リセット**: `docker volume rm agent-state`。所有権の継承は volume が空のときにしか
  起きないので、feature を直しても既存 volume は直らない
- **同時起動**: 複数コンテナを並行して立てると同じ状態に書く
- **`docker volume prune` では消えない**: 名前付き volume は `-a` を付けたときだけ対象

詳細な設計判断と検証手順は [docs/agent-state-feature-plan.md](../../../docs/agent-state-feature-plan.md) にある。
