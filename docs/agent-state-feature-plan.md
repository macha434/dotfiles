# devcontainer feature `macha-features` 実装プラン

`~/.claude` や `~/.codex` を名前付き Docker volume に載せ、すべての dev container で
共有・永続化する devcontainer feature を作る。ベースは公式テンプレート
[devcontainers/feature-starter](https://github.com/devcontainers/feature-starter)。

> **現状**: Step 1〜5 は実装・検証まで完了している（`features/` と
> `.github/workflows/features.yaml`）。残りは Step 6（GHCR へ publish して
> パッケージを public にする）と Step 7（ユーザー設定への登録）。

---

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

option で `mounts` を切れないため、**volume は 1 本だけ固定でマウントし、symlink の張り分けで
オン・オフを表現する**。

```
volume "agent-state"
   └─ mount → /var/lib/agent-state        ← ユーザー名に依存しない固定パス
                ├─ claude/  ←── symlink ── $HOME/.claude   (claude: true のとき)
                └─ codex/   ←── symlink ── $HOME/.codex    (codex: true のとき)
```

マウント先を `$HOME` の下に置かない理由: `mounts` の `target` は静的メタデータなので
`_REMOTE_USER_HOME` を展開できない。`/home/vscode/...` を決め打ちすると `remoteUser` が
`vscode` でないイメージで破綻する。`/var/lib/agent-state` なら誰が使っても同じで、
ユーザー依存の部分（symlink の張り先）は install スクリプトが動的に解決できる。

処理の分担:

| フェーズ | 実行者 | やること |
| --- | --- | --- |
| ビルド時 `install.sh` | root（volume はまだ無い） | `/var/lib/agent-state/<agent>/` を作って chown。ここの中身が初回コピーアップで volume に乗る。`$HOME/.<agent>` の symlink を張る。entrypoint を生成する |
| 起動時 `entrypoint.sh` | root（マウント後、毎回） | 既存 volume に足りないサブディレクトリを補う。uid がズレていたら直す。`exec "$@"` |

## 4. リポジトリ構成

このリポジトリ（`macha434/dotfiles`）に同居させる。公開名は
`ghcr.io/<owner>/<repo>/<featureId>` になるので、参照は
**`ghcr.io/macha434/dotfiles/macha-features:0.1`**。

```
features/
├── src/
│   └── macha-features/
│       ├── devcontainer-feature.json
│       └── install.sh
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

## 5. 実装ステップ

### Step 1: テンプレートを取得して骨組みを作る

`devcontainers/feature-starter` を "Use this template" せず、必要なファイルだけ手で写す
（既存リポジトリに同居させるため）。写すのは release / test の 2 つの workflow と
`src` / `test` のディレクトリ構造だけでよい。

devcontainer CLI をローカルに入れておく。

```bash
npm install -g @devcontainers/cli
devcontainer --version
```

### Step 2: `features/src/macha-features/devcontainer-feature.json`

```jsonc
{
  "id": "macha-features",
  "version": "0.1.0",
  "name": "Persistent agent state volume",
  "description": "Keeps ~/.claude and ~/.codex in a shared named volume across dev containers.",
  "documentationURL": "https://github.com/macha434/dotfiles/tree/main/features/src/macha-features",
  "options": {
    "claude": {
      "type": "boolean",
      "default": true,
      "description": "Persist ~/.claude"
    },
    "codex": {
      "type": "boolean",
      "default": false,
      "description": "Persist ~/.codex"
    }
  },
  "mounts": [
    {
      "source": "agent-state",
      "target": "/var/lib/agent-state",
      "type": "volume"
    }
  ],
  "entrypoint": "/usr/local/share/agent-state/entrypoint.sh"
}
```

`source` を固定文字列にしているのが「volume を固定する」の実体。プロジェクトごとに
分けたくなったら `agent-state-${devcontainerId}` にする。

### Step 3: `features/src/macha-features/install.sh`

```bash
#!/usr/bin/env bash
# ビルド時に root で走る。この時点で volume はまだ存在しない。
# ここで作った $STATE の中身と所有権が、空 volume の初回マウントで
# そのままコピーアップされる。これがこの feature の肝。
set -euo pipefail

USERNAME="${_REMOTE_USER:-vscode}"
HOME_DIR="${_REMOTE_USER_HOME:-/home/$USERNAME}"
STATE=/var/lib/agent-state

# option は大文字の環境変数で届く。値は文字列。
agents=()
[ "${CLAUDE:-false}" = "true" ] && agents+=(claude)
[ "${CODEX:-false}"  = "true" ] && agents+=(codex)

if [ ${#agents[@]} -eq 0 ]; then
    echo "agent-state: 有効な agent が無いので何もしない"
    exit 0
fi

install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE"

for name in "${agents[@]}"; do
    install -d -m 700 -o "$USERNAME" -g "$USERNAME" "$STATE/$name"

    # ベースイメージが既に設定を持っていれば volume 側へ移してから貼り替える
    if [ -d "$HOME_DIR/.$name" ] && [ ! -L "$HOME_DIR/.$name" ]; then
        cp -a "$HOME_DIR/.$name/." "$STATE/$name/"
        rm -rf "$HOME_DIR/.$name"
        chown -R "$USERNAME:$USERNAME" "$STATE/$name"
    fi

    ln -sfn "$STATE/$name" "$HOME_DIR/.$name"
    chown -h "$USERNAME:$USERNAME" "$HOME_DIR/.$name"
done

# _REMOTE_USER はビルド時にしか渡らないので、値を焼き込んで entrypoint を生成する
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

exec "$@"
INNER
} > /usr/local/share/agent-state/entrypoint.sh
chmod +x /usr/local/share/agent-state/entrypoint.sh
```

`exec "$@"` は必須。複数 feature の entrypoint は数珠つなぎに呼ばれるので、
落とすと後続の feature が動かなくなる。

chown の対象を `$STATE` だけでなく各サブディレクトリまで広げているのは意図的。
entrypoint は root で走るので、その直前の `mkdir` が作るディレクトリは `root:root` に
なる。`$STATE` 自体は正しい所有者のままなので、`$STATE` だけを条件にすると
**後から agent を有効化したケースを丸ごと取りこぼす**（実機で踏んだ）。

### Step 4: テストを書く

`features/test/macha-features/test.sh`（既定の option = claude のみ有効）:

```bash
#!/usr/bin/env bash
set -e
source dev-container-features-test-lib

check "claude の symlink がある"   bash -c '[ -L "$HOME/.claude" ]'
check "リンク先が正しい"           bash -c '[ "$(readlink "$HOME/.claude")" = /var/lib/agent-state/claude ]'
check "codex は既定で無効"         bash -c '[ ! -e "$HOME/.codex" ]'
check "state の所有者が自分"       bash -c '[ "$(stat -c %u /var/lib/agent-state)" = "$(id -u)" ]'
check "パーミッションが 700"       bash -c '[ "$(stat -c %a /var/lib/agent-state)" = 700 ]'
check "entrypoint が実行可能"      test -x /usr/local/share/agent-state/entrypoint.sh
check "書き込める"                 bash -c 'touch "$HOME/.claude/probe"'

reportResults
```

`features/test/macha-features/scenarios.json`（両方有効にした場合）:

```jsonc
{
  "both_enabled": {
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
    "features": {
      "macha-features": { "claude": true, "codex": true }
    }
  }
}
```

`features/test/macha-features/both_enabled.sh` で `~/.codex` の symlink も検査する。

実行:

```bash
devcontainer features test \
  --project-folder ./features \
  --features macha-features \
  --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
  --remote-user vscode
```

`--base-image` の既定は `ubuntu:focal` で `vscode` ユーザーが居ないため、明示が要る。
`--remote-user` も同様。位置引数でパスを渡す形は deprecated なので `--project-folder` を使う。

`--features` はローカルで 1 つに絞りたいときだけ付ける。CI では**あえて付けない**
（feature を増やしたときに列挙を直し忘れ、未テストのまま publish されるのを防ぐため）。

> `features test` は feature の `mounts` も適用する。つまり**テストを走らせると実際に
> `agent-state` volume が作られて残る**。ローカルで回したら `docker volume rm agent-state`
> で片付けること。放置すると次の本番利用でコピーアップが起きず、テスト時の空ディレクトリを
> 引き継いだ状態から始まる。
>
> ただし永続化・共有・uid の引き継ぎは test.sh の検査範囲外なので、Step 5 は別途通す。

### Step 5: 実コンテナでの手動検証

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

**1〜8 すべて実機で確認済み**（2026-08-28）。

- `devcontainer features test` … `test.sh` / `both_enabled` の両シナリオが pass
- `devcontainer up` で 2 つのワークスペースを立て、
  ws1 が書いたファイルが ws2 から見えること（共有）、
  ws1 のコンテナを破棄して作り直しても両方のファイルが残ること（永続化）を確認
- まっさらな volume で `/var/lib/agent-state` が `vscode:vscode 700` になり、
  sudo 無しで書けることを確認
- `chown -R 0:0` でわざと壊してからの自動復旧を確認

未検証で残っているのは publish 後の `defaultFeatures` 経由での参照だけ（Step 6 / Step 7）。

### Step 6: GHCR に publish する

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
- 公開されるタグは `0` / `0.1` / `0.1.0` / `latest`。0.x では破壊的変更が minor に
  乗るので、1.x での `:1` に相当する固定先は `:0.1` になる
- git タグは `feature_<id>_<version>` の形で打たれる。これには `contents: write` が要る
  （`read` だと publish は通ってタグ付けだけ失敗する）

### Step 7: ユーザー設定に登録する

```jsonc
// VS Code のユーザー設定 settings.json
"dev.containers.defaultFeatures": {
  "ghcr.io/macha434/dotfiles/macha-features:0.1": {
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
| option で `mounts` を切れない | codex を無効にしても volume 自体はマウントされる | symlink の張り分けで表現する（本プランの構成そのもの） |
| コピーアップは volume が空のときだけ | feature を直しても既存 volume は直らない | `docker volume rm agent-state` が唯一のリセット手段 |
| 初回初期化時の uid が volume に焼き付く | uid の違うイメージから使うと `0700` に弾かれる | entrypoint の chown で吸収。通常は `updateRemoteUserUID` が uid 1000 に寄せるので発生しない |
| entrypoint が root で走る保証は無い | `containerUser` が非 root だと chown が失敗する | ビルド時の準備だけが頼りになる。`mcr` 系の既定なら root なので問題ない |
| volume を全コンテナで共有する | 同時起動時は `history.jsonl` や `sessions/` に複数が書く | 1 台で複数セッションを開くのと同じ状況。許容する。分けたいなら `${devcontainerId}` |
| 認証情報が volume に平文で残る | docker にアクセスできれば読める | docker group は実質 root 相当なので、このマシン内では新たな露出ではない |

`docker volume prune` で消える心配は無い。名前付き volume は `-a` を付けたときだけ対象。

## 7. 拡張するとき

agent を 1 つ足す手順は 2 箇所だけ:

1. `devcontainer-feature.json` の `options` に boolean を 1 つ追加
2. `install.sh` の `agents=()` 判定に 1 行追加

数が増えて boolean が並ぶのが煩わしくなったら、`"type": "string"` の
`"agents": "claude,codex"` に寄せて `IFS=,` で分解する形に組み替える。
その場合 `options` のスキーマ変更なので major を上げる。
