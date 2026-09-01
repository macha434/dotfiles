# macha-features

`~/.claude` と `~/.codex` を名前付き Docker volume に載せて、dev container を作り直しても
消えないようにする。volume 名を固定しているので、プロジェクトをまたいで同じ状態を共有する
（ログインは 1 回で済む）。オプションで agent の CLI 導入とステータスラインの適用も行う。

```jsonc
"features": {
    "ghcr.io/macha434/dotfiles/macha-features:0.5": {
        "claude": true,
        "codex": false
    }
}
```

VS Code のユーザー設定に書けば、以後このマシンで作るすべての dev container に効く。

```jsonc
"dev.containers.defaultFeatures": {
    "ghcr.io/macha434/dotfiles/macha-features:0.5": { "claude": true }
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
                ├─ claude/
                │    ├─ (ディレクトリ本体)  ←── symlink ── $HOME/.claude
                │    └─ .claude.json        ←── symlink ── $HOME/.claude.json
                └─ codex/  ←── symlink ── $HOME/.codex
```

マウント先を `$HOME` の下に置いていないのは、`mounts` の `target` が `_REMOTE_USER_HOME` を
展開できないため。`/home/vscode` を決め打ちすると `remoteUser` が違うイメージで壊れる。

`~/.claude.json`（`oauthAccount` を含むグローバル設定）は `~/.claude/` の**外**、ホーム直下の
別ファイルにある。`~/.claude/.credentials.json` 自体は `~/.claude` の volume 化で持続するが、
ログイン判定は `~/.claude.json` の `oauthAccount` も見ているため、これを見落とすとコンテナを
作り直すたびに再ログインを求められる（実機で確認済み）。ディレクトリと同じ考え方で、ファイルと
して個別に symlink している。Codex 側には `~/.codex/` の外にこの種のファイルは無い。

所有権は実行時に直しているのではなく、**空の volume がマウント先の所有権を継承する**性質を
使っている。ビルド時に `/var/lib/agent-state` を remote user 所有で作っておけば、初回
マウント時にその所有権ごと volume にコピーアップされるので、sudo 無しで書ける状態から始まる。

## 3 つの実行タイミング

やることによって走る場所が違う。どれも理由がある。

| いつ | 何を | なぜそこか |
| --- | --- | --- |
| **ビルド時** `install.sh` (root) | volume のマウント先を用意、symlink（`~/.claude` `~/.codex` `~/.claude.json`）、Claude Code CLI、settings.json/keybindings.json/statusline スクリプトのテンプレート配置 | コピーアップに乗せるにはビルド時でないといけない。Claude Code は `~/.local/` に入る（volume の外）のでイメージに焼ける |
| **起動ごと** `entrypoint.sh` (root) | 所有権の補正、settings.json へのテンプレートマージ、keybindings.json の symlink | `settings.json` は volume の中。ビルド時に書くとコピーアップが起きる初回にしか届かない |
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

インストーラは最後に「Start Codex now? [y/N]」と訊いてくる。postCreate に答える相手は
居ないので、既定の N が黙って選ばれるように三重に手を打っている。

1. `curl | sh` をやめてファイルに落としてから実行する。パイプのままだとインストーラの
   `read` が「まだ実行していないスクリプト自身の続き」を食う
2. stdin を `/dev/null` にする。stdin から読む実装ならこれで EOF になる
3. `setsid -w` で制御端末を切り離す。`/dev/tty` を直接開く実装には 2 が効かない。
   `-w` が無いと子を待たず終了ステータスも拾えないので必ず付ける

`setsid` が無い環境では 1 と 2 だけで進む。

### config.toml

正は**リポジトリルートの [`codex/config.toml`](../../../codex/) 側**で、[`claude/settings.json`](../../../claude/settings.json)
と対になる内容にしている。feature 用のコピーは他と同じく `features/sync-assets.sh` が生成し、
`install.sh` が `$SHARE/codex-config.toml` としてイメージ側に置く。

`claude/settings.json` と違い、**`$STATE/codex/config.toml` に無いときだけ**
`ensure-codex.sh`（postCreate、volume マウント後）が置く。毎起動上書きしない。Codex CLI は
config.toml の一部（キーバインドのカスタマイズなど）を自分で書き戻すため、settings.json と
同じように毎起動テンプレートを当てると、その変更が消えてしまう。TOML 用の jq に相当する
マージツールも無いため、この「無いときだけ置く」方式にした。

配置を `install.sh`（ビルド時）ではなく `ensure-codex.sh`（postCreate）でやっているのが
要点。ビルド時は volume がまだ存在しないので、「無いから置く」は image 側にしか反映されず、
volume の初回コピーアップに委ねる形になる。だが volume が（`claude/` だけでも）既に何か
持っていればコピーアップ自体が起きないため、`codex/config.toml` は永久に届かない。
`ensure-codex.sh` は volume マウント後・コンテナ作成のたびに走るので、実際の volume の
状態を見て判断できる。

このおかげで、**Codex の分だけをリセットしたいとき、volume ごと消す必要は無い**。
`~/.claude.json` を巻き込みたくない（＝ Claude Code の再ログインを避けたい）場合はこちら。

```bash
docker run --rm -v agent-state:/data alpine rm -f /data/codex/config.toml
```

のあとコンテナ内で `bash /usr/local/share/macha-features/ensure-codex.sh` を実行するか、
コンテナを作り直す（`postCreateCommand` はコンテナ作成のたびに走るので、単なる再起動では
発火しない）。

## settings.json / keybindings.json / ステータスライン

正は**リポジトリルートの [`claude/`](../../../claude/) 側**（`settings.json`、
`keybindings.json`、`statusline-command.sh`）で、dotfiles として `install.sh` が
ホストの `~/.claude/` にも配置する。feature 用のコピーは
[`features/sync-assets.sh`](../../sync-assets.sh) が
[`features/assets.tsv`](../../assets.tsv) の対応表に従って生成する（gitignore 済み）。

feature の tarball には feature ディレクトリ配下しか入らず、しかも packaging は symlink を
symlink のまま tar に入れる。リポジトリ内 symlink で共有すると公開された feature が宙を指す
リンクを抱えるので、実体のコピーが要る。同期を忘れるとビルド時に落ちる。

3 つとも `/usr/local/share/macha-features/claude-*` に配置する。volume の外に置くのが要点で、
volume に置くと更新が 2 回目以降のコンテナに届かない。イメージ側なら rebuild のたびに最新になる。

**settings.json** はコンテナ起動ごとに `entrypoint.sh` がテンプレート全体を jq でマージする
（`.既存 * .テンプレート`）。テンプレートに無いキー（Claude Code 自身が足したもの、例えば
MCP サーバーの承認履歴）は残り、テンプレートにあるキーは host の `install_file`
（symlink での単純上書き）と同じ力関係でテンプレート側が勝つ。ただし `statusLine` だけは
マージ後に強制上書きする。テンプレートの `statusLine.command` は host 向けの
`~/.claude/statusline-command.sh` を指しており、このイメージには存在しないため。
`jq` が無い環境ではテンプレートとのマージができないので、`settings.json` が無いときに
`statusLine` だけの最小構成を書いて警告を出す。この経路に頼らないよう、`jq` 自体は
`install.sh`（ビルド時、root）が `apt-get` で入れる。base image が既に持っていれば
何もしない。`apt-get` の無い base image では入れられない旨を警告するだけで、ビルドは
落とさない。

**keybindings.json** は Claude Code 自身が書き換えることの無い静的な設定なので、
settings.json と違ってマージは要らない。`~/.claude/keybindings.json` を
`claude-keybindings.json` への symlink にするだけで、jq に頼らず rebuild のたびに最新になる。

**statusline-command.sh** は `~/.claude/settings.json` の `statusLine` が
`claude-statusline.sh` を指すことで使われる（上記のとおり、これはテンプレートではなく
マージ後に強制されるパス）。

`refreshInterval: 1` を付けている。レート制限の残り時間と経過ペースを進めるために要る。
イベント駆動だけだとアイドル中に表示が止まる。

### 表示内容

```
NORMAL                                              ← vim モード
claude-opus-5 · high · fast off · ctx 8%            ← モデル ID / effort / fast / コンテキスト
5h 23% (4h00m)   7d 41% (3d00h)                     ← レート制限
```

レート制限の色は**経過ぶんの線形ペース**との比較で決まる。5 時間窓なら 1 時間あたり 20% が
等速なので、2 時間経過して 40% を超えていれば赤、30%（0.5 時間ぶん手前）を超えていれば黄色。
3 時間経過なら赤 60% / 黄 50%。7 日窓も同じ考え方を日単位で適用する。

コンテキストは 90% 以上で赤、70% 以上で黄色。存在しないフィールドは `--` になる
（vim モード無効、effort 非対応モデル、最初の API 応答前など）。

表示を変えたいときは `claude/statusline-command.sh` を編集する。ホスト側は
`./install.sh claude` で即反映される。**コンテナ側に反映するには `version` を上げること。**
複製元を変えると CI は起動するが、version が同じままだと publish はスキップされる。

Codex 側にも `codex/config.toml` の `[tui] status_line` として同等の設定がある（[config.toml](#configtoml) 参照）。
ただし表示項目を選ぶだけの仕組みで、並び順や書式は指定できない。

## 運用

- **リセット**: `docker volume rm agent-state`。所有権の継承は volume が空のときにしか
  起きないので、feature を直しても既存 volume は直らない
- **同時起動**: 複数コンテナを並行して立てると同じ状態に書く
- **`docker volume prune` では消えない**: 名前付き volume は `-a` を付けたときだけ対象

詳細な設計判断と検証手順は [docs/agent-state-feature-plan.md](../../../docs/agent-state-feature-plan.md) にある。
