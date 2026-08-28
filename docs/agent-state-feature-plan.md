# devcontainer feature `macha-features` 設計メモ

`~/.claude` と `~/.codex` を名前付き Docker volume に載せ、すべての dev container で
共有・永続化する devcontainer feature。オプションで agent の CLI 導入と
ステータスライン適用も行う。ベースは公式テンプレート
[devcontainers/feature-starter](https://github.com/devcontainers/feature-starter)。

> **現状**: 実装・公開済み。`ghcr.io/macha434/dotfiles/macha-features` で公開している。
> コードの正は `features/src/macha-features/` にあり、このドキュメントは
> **なぜそうなっているか**だけを残す。使い方は
> [features/src/macha-features/README.md](../features/src/macha-features/README.md)。


## 1. ゴール

- dev container を作り直しても agent の設定・認証・履歴が消えない
- プロジェクトをまたいで同じ state を使う（ログインは 1 回で済む）
- `dev.containers.defaultFeatures` に 1 行書くだけで全コンテナに効く
- どの agent を載せるかは feature の option で切り替える

## 2. 前提として確定していること

| 事項 | 結論 | 根拠 |
| --- | --- | --- |
| ホスト環境 | WSL 内のネイティブ docker (Ubuntu 24.04 / 29.5.2)、uid 1000 | `docker info` / `id` で実測 |
| 空の named volume の所有権 | マウント先がイメージに存在すればその所有権・パーミッション・中身を継承。無ければ `root:root 0755` | 手元の docker で A/B 比較して確認 |
| 継承のタイミング | volume が空の初回だけ | 同上 |
| volume への `chown` | ホスト側に実体が無いので安全（bind mount とはここが違う） | — |
| feature の option | install スクリプトに大文字の環境変数として届く。値は `"true"` / `"false"` の文字列 | Features 仕様 |
| feature の `mounts` | 静的メタデータ。option で出し分けできない | CLI バンドルを確認した範囲で option 差し込みの経路が無い |
| `dev.containers.defaultFeatures` | `type: object` / `scope: application`。値の形は `devcontainer.json` の `features` と同一 | 拡張の `package.json` |

## 3. 採用する構成

option で `mounts` を切れないため、**volume は 1 本だけ固定でマウントする**。

```
volume "agent-state"
   └─ mount → /var/lib/agent-state        ← ユーザー名に依存しない固定パス
                ├─ claude/  ←── symlink ── $HOME/.claude
                └─ codex/   ←── symlink ── $HOME/.codex
```

**永続化は option に関わらず常に行う。** 当初は symlink の張り分けでオン・オフを
表現していたが、`mounts` がどのみち無条件である以上、片方だけ symlink を張らないのは
一貫性が無い。option が決めるのは **CLI を入れるかどうかと statusline を当てるか**だけ。

マウント先を `$HOME` の下に置かない理由: `mounts` の `target` は静的メタデータなので
`_REMOTE_USER_HOME` を展開できない。`/home/vscode/...` を決め打ちすると `remoteUser` が
`vscode` でないイメージで破綻する。`/var/lib/agent-state` なら誰が使っても同じで、
ユーザー依存の部分（symlink の張り先）は install スクリプトが動的に解決できる。

処理の分担:

| フェーズ | 実行者 | やること |
| --- | --- | --- |
| ビルド時 `install.sh` | root（volume はまだ無い） | `/var/lib/agent-state/<agent>/` を作って chown。ここの中身が初回コピーアップで volume に乗る。`$HOME/.<agent>` の symlink。Claude Code CLI。entrypoint と statusline の配置 |
| 起動時 `entrypoint.sh` | root（マウント後、毎回） | 既存 volume に足りないサブディレクトリを補う。uid がズレていたら直す。`statusLine` をマージする。`exec "$@"` |
| 作成後 `ensure-codex.sh` | remote user（`postCreateCommand`） | Codex CLI を volume に無いときだけ入れ、ランチャを張り直す |

## 4. リポジトリ構成

このリポジトリ（`macha434/dotfiles`）に同居させる。公開名は
`ghcr.io/<owner>/<repo>/<featureId>` になるので、参照は
**`ghcr.io/macha434/dotfiles/macha-features:0.2`**。

```
features/
├── src/
│   └── macha-features/
│       ├── devcontainer-feature.json
│       ├── install.sh          # ビルド時 (root)
│       ├── entrypoint.sh       # 起動ごと (root)
│       ├── ensure-codex.sh     # postCreateCommand (remote user)
│       ├── statusline/claude.sh
│       └── README.md
└── test/
    └── macha-features/
        ├── test.sh
        ├── scenarios.json
        └── both_enabled.sh
.github/workflows/
└── features.yaml          # test → release を 1 本のパイプラインにする
```

テンプレートは `src/` をリポジトリ直下に置く前提なので、workflow 側で
`base-path-to-features: ./features/src` を指定してずらす。

> 判断メモ: リポジトリを分ける技術的な必要は無い。`macha434/dotfiles` は public なので
> GHCR パッケージを public にするのも素直（private repo だとパッケージ可視性を個別に
> いじる話が生じるが、その論点自体が無い）。workflow は `paths:` で `features/src/**` に
> 絞るので、dotfiles 側の commit で余計な release も走らない。
>
> 唯一の実質的なコストは参照名に repo 名が入ること（`ghcr.io/macha434/dotfiles/macha-features`）。
> 後から専用リポジトリへ移すと ref が変わり、`defaultFeatures` と利用側の
> `devcontainer.json` を書き換えることになるので、名前は実質的に固定資産と考えておく。
> feature が増えた・dotfiles を private にしたくなった・feature 単体で issue を
> 受けたくなった、のいずれかが起きたら分ける。

---

## 5. 実装

コードの正はリポジトリのファイル。ここでは「どれがどのタイミングで走るか」だけ示す。

| ファイル | いつ / 誰が | 役割 |
| --- | --- | --- |
| `src/macha-features/install.sh` | ビルド時 / root | volume のマウント先を用意して symlink。Claude Code CLI。entrypoint と statusline の配置 |
| `src/macha-features/entrypoint.sh` | 起動ごと / root | 所有権の補正。`statusLine` 設定のマージ |
| `src/macha-features/ensure-codex.sh` | 作成後 / remote user | Codex CLI（`postCreateCommand`） |
| `src/macha-features/statusline/claude.sh` | — | ステータスラインの本体。イメージ側に配置される |

### なぜ 3 つに分かれるか

**ビルド時でないといけないもの**: volume のコピーアップに乗せる中身と所有権。これが
この feature の肝で、実行時の chown が要らない理由。

**起動ごとでないといけないもの**: `~/.claude/settings.json` への `statusLine` 設定。
volume の中にあるので、ビルド時に書くとコピーアップが起きる初回にしか届かない。
スクリプト本体のほうは volume の外（`/usr/local/share/macha-features/`）に置くので、
settings.json 側は不変なパスを指すだけでよく、陳腐化しない。

**作成後でないといけないもの**: Codex CLI。インストーラがバイナリ本体を
`~/.codex/packages/` に置く、つまり実体が volume の中に入るため、ビルド時に入れても
2 回目以降のコンテナには届かず `~/.local/bin/codex` が宙を指す（実測で確認）。
entrypoint でやるとダウンロードがコンテナ起動をブロックし、テストハーネスとも競合した。
`postCreateCommand` なら remote user で走り、devcontainer が完了を待つ。

Claude Code は `~/.local/share/claude/` に入る（volume の外）ので、この問題が無く
ビルド時に入れられる。同じ「CLI を入れる」でも扱いが分かれるのはこの差による。

### テスト

```bash
devcontainer features test \
  --project-folder ./features \
  --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
  --remote-user vscode
```

`--base-image` の既定は `ubuntu:focal` で `vscode` ユーザーが居ないため、明示が要る。
`--features` はローカルで 1 つに絞りたいときだけ付ける。CI では**あえて付けない**
（feature を増やしたときに列挙を直し忘れ、未テストのまま publish されるのを防ぐため）。

> `features test` は feature の `mounts` も `entrypoint` も適用する。つまり**テストを
> 走らせると実際に `agent-state` volume が作られて残る**。ローカルで回したら
> `docker volume rm agent-state` で片付けること。放置すると次の本番利用でコピーアップが
> 起きず、テスト時の空ディレクトリを引き継いだ状態から始まる。


### 実コンテナでの手動検証

```bash
mkdir -p /tmp/agent-state-check/.devcontainer
cat > /tmp/agent-state-check/.devcontainer/devcontainer.json <<'JSON'
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "./features/src/macha-features": { "claude": true }
  }
}
JSON
```

publish 前はローカルパス参照でよい（相対パス指定の feature は `devcontainer.json` からのみ
使える。`defaultFeatures` からは使えないので、そこは publish 後に切り替える）。

検証項目:

1. `docker volume rm agent-state` してまっさらから起動する
2. `id` と `stat -c '%u %a' /var/lib/agent-state` が一致していて `700` であること
3. `readlink ~/.claude` が `/var/lib/agent-state/claude` を指すこと
4. `touch ~/.claude/probe` が sudo 無しで通ること
5. コンテナを捨てて作り直し、`probe` が残っていること ← **永続化の本命**
6. 別のワークスペースで `devcontainer up` して、同じ `probe` が見えること ← **共有の本命**
7. `codex: true` を足して再作成し、`~/.codex` が生えて既存の `claude/` が壊れないこと
   ← **後から追加**の経路。コピーアップが効かないので entrypoint 頼みになる
8. `chown -R 0:0 /var/lib/agent-state` でわざと壊してから再起動し、自動復旧すること

### 検証済みの範囲

`devcontainer features test` の 2 シナリオ 27 項目が pass。加えて実コンテナで確認済み:

| 項目 | 結果 |
| --- | --- |
| まっさらな volume の所有権 | `vscode:vscode 700`、sudo 無しで書ける |
| 別ワークスペースからの共有 | ws1 が書いたファイルが ws2 から見える |
| コンテナ破棄 → 再作成 | ファイルが残る |
| 後から agent を追加 | 既存を壊さずにサブディレクトリが生える |
| `chown -R 0:0` で破壊 | 起動時に自動復旧 |
| 既存 `~/.claude` を持つイメージ | volume 側へ引き継がれる |
| Claude / Codex CLI | 両方起動する。statusLine も当たる |
| 2 回目のコンテナ | Codex を再ダウンロードしない（30 秒 → 3 秒） |

### GHCR への publish

test と release は **1 ファイルにまとめる**。`needs:` は同一 workflow 内でしか張れず、
別ファイルに分けるとテストの成否と無関係に publish が走ってしまうため。

`.github/workflows/features.yaml`:

```yaml
name: Features

on:
  workflow_dispatch:
  pull_request:
    paths:
      - 'features/**'
      - '.github/workflows/features.yaml'
  push:
    branches: [main]
    paths:
      - 'features/**'
      - '.github/workflows/features.yaml'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install devcontainer CLI
        run: npm install -g @devcontainers/cli
      # --features で絞らない。feature が増えたときの直し忘れを防ぐため。
      - name: Test features
        run: |
          devcontainer features test \
            --project-folder ./features \
            --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
            --remote-user vscode

  release:
    needs: test
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4
      - name: Publish features
        uses: devcontainers/action@v1
        with:
          publish-features: 'true'
          base-path-to-features: ./features/src
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`release` の対象を `features/src/**` に絞っていないのは、publish が冪等
（同一 version はスキップ）で、`features/test/**` だけの変更なら空振りして終わるため。
絞るより、テストを通った変更が必ず publish 経路を通るほうが事故が少ない。

publish 後にやること（忘れやすい）:

- GHCR のパッケージは**既定で private**。GitHub の Packages 設定から `macha-features` を
  public にしないと、pull のたびに認証を求められる
- 公開されるタグは `0` / `0.2` / `0.2.0` / `latest`。0.x では破壊的変更が minor に
  乗るので、1.x での `:1` に相当する固定先は `:0.2` になる
- git タグは `feature_<id>_<version>` の形で打たれる。これには `contents: write` が要る
  （`read` だと publish は通ってタグ付けだけ失敗する）

### ユーザー設定への登録

```jsonc
// VS Code のユーザー設定 settings.json
"dev.containers.defaultFeatures": {
  "ghcr.io/macha434/dotfiles/macha-features:0.2": {
    "claude": true,
    "codex": false
  }
}
```

`scope: application` なので、以後このマシンで作るすべての dev container に効く。

---

## 6. 既知の制約

| 制約 | 影響 | 対処 |
| --- | --- | --- |
| option で `mounts` / `dependsOn` を切れない | codex を無効にしても volume はマウントされる。他 feature の条件付き取り込みもできない | 永続化は無条件と割り切り、option は CLI 導入だけを決める |
| Codex がバイナリを `~/.codex/` に置く | 実体が volume の中に入るので、ビルド時に入れても 2 回目以降のコンテナで宙を指す | `postCreateCommand` で volume に無いときだけ入れる。ランチャは毎回張り直す |
| entrypoint でのネットワーク処理はコンテナ起動をブロックする | `features test` がダウンロード中にテストを開始して落ちた | 時間のかかる処理は `postCreateCommand` に置く |
| コピーアップは volume が空のときだけ | feature を直しても既存 volume は直らない | `docker volume rm agent-state` が唯一のリセット手段 |
| 初回初期化時の uid が volume に焼き付く | uid の違うイメージから使うと `0700` に弾かれる | entrypoint の chown で吸収。通常は `updateRemoteUserUID` が uid 1000 に寄せるので発生しない |
| entrypoint が root で走る保証は無い | `containerUser` が非 root だと chown が失敗する | ビルド時の準備だけが頼りになる。`mcr` 系の既定なら root なので問題ない |
| volume を全コンテナで共有する | 同時起動時は `history.jsonl` や `sessions/` に複数が書く | 1 台で複数セッションを開くのと同じ状況。許容する。分けたいなら `${devcontainerId}` |
| 認証情報が volume に平文で残る | docker にアクセスできれば読める | docker group は実質 root 相当なので、このマシン内では新たな露出ではない |

`docker volume prune` で消える心配は無い。名前付き volume は `-a` を付けたときだけ対象。

## 7. 拡張するとき

agent を 1 つ足すときに触る場所:

1. `devcontainer-feature.json` の `options` に boolean を 1 つ追加
2. `install.sh` の `AGENTS=()` に名前を追加（永続化はここだけで済む）
3. CLI を入れるなら、その CLI が**どこにバイナリを置くか**を先に確かめる
   - `$HOME/.local/` など volume の外 → `install.sh` でビルド時に入れる
   - `~/.<agent>/` の中 → volume と衝突するので `ensure-codex.sh` と同じ形にする

3 を飛ばすと Codex で踏んだのと同じ壊れ方をする。`~/.local/bin/<cli>` の
リンク先が volume の中を指していないか、`readlink -f` で確かめるのが早い。

数が増えて boolean が並ぶのが煩わしくなったら、`"type": "string"` の
`"agents": "claude,codex"` に寄せて `IFS=,` で分解する形に組み替える。
その場合 `options` のスキーマ変更なので minor を上げる（0.x では破壊的変更が minor）。
