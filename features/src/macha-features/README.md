# macha-features

`~/.claude`・`~/.codex`・`~/.copilot` を名前付き Docker volume に載せて、dev container を
作り直しても消えないようにする。volume 名を固定しているので、プロジェクトをまたいで同じ状態を
共有する（ログインは 1 回で済む）。オプションで agent の CLI 導入とステータスラインの適用も行う。

```jsonc
"features": {
    "ghcr.io/macha434/dotfiles/macha-features:0.6": {
        "claude": true,
        "codex": false,
        "copilot": false
    }
}
```

VS Code のユーザー設定に書けば、以後このマシンで作るすべての dev container に効く。

```jsonc
"dev.containers.defaultFeatures": {
    "ghcr.io/macha434/dotfiles/macha-features:0.6": { "claude": true }
}
```

## Options

| id | type | default | 説明 |
| --- | --- | --- | --- |
| `claude` | boolean | `true` | Claude Code CLI を入れ、ステータスラインを当てる |
| `codex` | boolean | `false` | Codex CLI を入れる |
| `copilot` | boolean | `false` | GitHub Copilot CLI を入れ、ステータスラインを当てる |

**永続化はオプションに関わらず常に行う。** `~/.claude`・`~/.codex`・`~/.copilot` はどの値でも
volume に載る。オプションが決めるのは CLI を入れるかどうかと設定を当てるかどうかだけ。

## しくみ

```
volume "agent-state"
   └─ mount → /var/lib/agent-state
                ├─ claude/
                │    ├─ (ディレクトリ本体)  ←── symlink ── $HOME/.claude
                │    └─ .claude.json        ←── symlink ── $HOME/.claude.json
                ├─ codex/    ←── symlink ── $HOME/.codex
                └─ copilot/  ←── symlink ── $HOME/.copilot
```

マウント先を `$HOME` の下に置いていないのは、`mounts` の `target` が `_REMOTE_USER_HOME` を
展開できないため。`/home/vscode` を決め打ちすると `remoteUser` が違うイメージで壊れる。

`~/.claude.json`（`oauthAccount` を含むグローバル設定）は `~/.claude/` の**外**、ホーム直下の
別ファイルにある。`~/.claude/.credentials.json` 自体は `~/.claude` の volume 化で持続するが、
ログイン判定は `~/.claude.json` の `oauthAccount` も見ているため、これを見落とすとコンテナを
作り直すたびに再ログインを求められる（実機で確認済み）。ディレクトリと同じ考え方で、ファイルと
して個別に symlink している。Codex 側には `~/.codex/` の外にこの種のファイルは無い。Copilot も
設定・状態はすべて `~/.copilot/`（`COPILOT_HOME` で変えられる）の下にある。`~/.cache/copilot/`
も使うがこちらは CLI 本体のパッケージ置き場で、消えても再取得されるだけなので載せていない。

所有権は実行時に直しているのではなく、**空の volume がマウント先の所有権を継承する**性質を
使っている。ビルド時に `/var/lib/agent-state` を remote user 所有で作っておけば、初回
マウント時にその所有権ごと volume にコピーアップされるので、sudo 無しで書ける状態から始まる。

## 3 つの実行タイミング

やることによって走る場所が違う。どれも理由がある。

| いつ | 何を | なぜそこか |
| --- | --- | --- |
| **ビルド時** `install.sh` (root) | volume のマウント先を用意、symlink（`~/.claude` `~/.codex` `~/.copilot` `~/.claude.json`）、Claude Code CLI と Copilot CLI、設定テンプレートと statusline スクリプトの配置 | コピーアップに乗せるにはビルド時でないといけない。Claude Code と Copilot は `~/.local/` に入る（volume の外）のでイメージに焼ける |
| **起動ごと** `entrypoint.sh` (root) | 所有権の補正、settings.json と config.json へのテンプレートマージ、keybindings.json の symlink | どちらも volume の中。ビルド時に書くとコピーアップが起きる初回にしか届かない |
| **作成後** `ensure-codex.sh` (remote user) | Codex CLI | 下記 |

### Codex だけ扱いが違う理由

3 つのうち Codex だけが postCreate なのは、インストーラの置き先が違うから。Claude Code と
Copilot はどちらも `~/.local/`（と Copilot は `~/.cache/copilot/`）に入る。volume の外なので
イメージに焼ける。Copilot を postCreate にすると、コンテナを作り直すたびに 300MB 近い
ダウンロードが走ることになる。

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
落とさない。`copilot` だけを有効にした場合も jq は入る（statusline スクリプトと
config.json のマージの両方で要る）。

**Copilot の `~/.copilot/config.json` もまったく同じ扱い**（`entrypoint.sh` の
`apply_json_config` を両者で共有している）。Copilot も `/model` `/theme` `/vim` や
`trustedFolders` を自分で config.json に書き戻す生きた設定なので、Codex の
「無いときだけ置く」ではなく Claude 側の毎起動マージに寄せている。JSON なので jq が
そのまま使える。違いは `refreshInterval` を付けないことだけで、理由は後述。

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

Copilot 側は Claude とスキーマまで同じ（`type` / `command` / `refreshInterval` / `padding`、
stdin に JSON を渡して stdout を読む）ので、[`copilot/statusline-command.sh`](../../../copilot/)
として同じ作りのスクリプトを置いている。ただし**渡ってくる JSON の中身は違う**ので、
スクリプトは共有できず 2 本ある。

```
claude-sonnet-5 · allow-all off · ctx 42%    ← モデル ID / パーミッション / コンテキスト
ai 1.25   premium 7                          ← 消費
```

Claude 版が 3 行なのに対し 2 行なのは、対応するフィールドが JSON に無いため。

| Claude 版 | Copilot 版 |
| --- | --- |
| 1 行目 vim モード | **無し。** `vim.mode` に相当するものが渡らない（`editorMode: "vim"` 自体は効く） |
| 2 行目 モデル / effort / fast / ctx | モデル / **allow-all** / ctx。effort と fast mode は渡らないので、代わりに `allow_all_enabled`（全許可モードかどうか）を出している |
| 3 行目 レート制限 5h / 7d | 消費（AI クレジットと premium リクエスト）。窓ごとの上限も reset 時刻も渡らないため、ペース比較も色分けもできず値をそのまま出す |

`refreshInterval` を付けていないのはこの 3 行目のため。Claude 側はレート制限の残り時間を
進める必要があるが、Copilot 側にはそういう放っておくと古くなる表示が無いので、イベント駆動の
ままでよい。コンテキスト率の色（90% 以上で赤、70% 以上で黄色）は Claude 版と揃えている。

## Copilot の config.json

正は**リポジトリルートの [`copilot/config.json`](../../../copilot/)** で、
`claude/settings.json` と対になる内容にしている。対応表と、対応するものが無いキーの一覧は
[`install.d/copilot.sh`](../../../install.d/copilot.sh) の頭に置いてある（config.json は
素の JSON でコメントを書けないため）。要点だけ:

| Claude | Copilot |
| --- | --- |
| `model: "sonnet"` | `model: "auto"`。**ここだけ Claude に寄せていない**（Copilot に選ばせる。ID を直接書くこともできるが、Codex と同じくファミリーエイリアスが無いので新しい版が出るたびに更新が要る） |
| `effortLevel: "high"` | `effortLevel: "high"`（`alwaysThinkingEnabled` はこちらに含まれる） |
| `editorMode: "vim"` | `editorMode: "vim"`（キー名まで同じ） |
| `permissions.defaultMode: "auto"` | `defaultPermissionMode: "assisted"` |
| `attribution.commit: ""` | `includeCoAuthoredBy: false` |
| `theme: "dark"` | **無し。** dark を固定する手段が無い（`github` だけが専用配色を持つが端末に問い合わせて明暗を自動切替、`default` と `dim` は端末の 16 色そのまま） |
| `tui: "fullscreen"` | **設定不要。** Copilot は TUI 起動時に必ず alt screen へ入る |
| `fastMode` | **無し。** 速い版が要るならモデル ID 側で選ぶ |
| `attribution.pr` / `sessionUrl` | **無し。** |

`experimental: true` を入れているのは `editorMode` と `defaultPermissionMode` のためで、
Claude 側に対応するキーがあるわけではない。どちらも実験機能のフラグ越しに有効化されるので、
これが無いと黙って効かない。フラグが下りていない環境では `defaultPermissionMode` は警告を
出して `manual` にフォールバックし、`editorMode` は無視される（設定自体はエラーにならない）。

CLI のインストールは remote user で走らせている。Claude Code と同じく、失敗すると
ビルドが落ちる。`curl | bash` にせず一度ファイルへ落としてから実行しているのは
`ensure-codex.sh` と同じ理由（[Codex だけ扱いが違う理由](#codex-だけ扱いが違う理由)参照）。
`curl ... | bash </dev/null` のようにパイプの最後へ直接リダイレクトを付けると、
リダイレクトはパイプ接続より優先されるため、bash は curl の出力ではなく `/dev/null`
を読むことになりインストーラを一切実行しない。curl 側も書き込み先を読む相手が
いなくなって失敗する（実測: `curl: (23) Failure writing output to destination`。
CI で実際に踏んだ）。

## 運用

- **リセット**: `docker volume rm agent-state`。所有権の継承は volume が空のときにしか
  起きないので、feature を直しても既存 volume は直らない
- **同時起動**: 複数コンテナを並行して立てると同じ状態に書く
- **`docker volume prune` では消えない**: 名前付き volume は `-a` を付けたときだけ対象

詳細な設計判断と検証手順は [docs/agent-state-feature-plan.md](../../../docs/agent-state-feature-plan.md) にある。
