# macha-features

`~/.claude`・`~/.codex`・`~/.copilot`・`~/.config/gh`（`gh auth login` の資格情報）を
名前付き Docker volume に載せて、dev container を作り直しても消えないようにする。volume 名を
固定しているので、プロジェクトをまたいで同じ状態を共有する（ログインは 1 回で済む）。オプションで
agent の CLI 導入とステータスラインの適用も行う。

```jsonc
"features": {
    "ghcr.io/macha434/dotfiles/macha-features:0.12": {
        "claude": true,
        "codex": false,
        "copilot": false,
        "herdr": false,
        "graphify": false,
        "claudeSkills": false,
        "codexSkills": false,
        "copilotSkills": false
    }
}
```

VS Code のユーザー設定に書けば、以後このマシンで作るすべての dev container に効く。

```jsonc
"dev.containers.defaultFeatures": {
    "ghcr.io/macha434/dotfiles/macha-features:0.12": { "claude": true }
}
```

## Options

| id | type | default | 説明 |
| --- | --- | --- | --- |
| `claude` | boolean | `true` | Claude Code CLI を入れ、ステータスラインを当てる |
| `codex` | boolean | `false` | Codex CLI を入れる |
| `copilot` | boolean | `false` | GitHub Copilot CLI を入れ、ステータスラインを当てる |
| `herdr` | boolean | `false` | herdr を入れ、既定の config.toml を置く |
| `graphify` | boolean | `false` | [Graphify](https://github.com/Graphify-Labs/graphify)（`graphifyy`）を入れ、有効な `claude`/`codex`/`copilot` にスキルとして登録する |
| `claudeSkills` | boolean | `false` | [`claude-skills.json`](./claude-skills.json) に載っている Claude Code plugin を全部入れる(`claude` が有効な場合のみ意味を持つ) |
| `codexSkills` | boolean | `false` | [`codex-skills.json`](./codex-skills.json) に載っている Codex plugin を全部入れる(`codex` が有効な場合のみ意味を持つ) |
| `copilotSkills` | boolean | `false` | [`copilot-skills.json`](./copilot-skills.json) に載っている Copilot plugin を全部入れる(`copilot` が有効な場合のみ意味を持つ)。今のところカタログは空 |

**永続化はオプションに関わらず常に行う。** `~/.claude`・`~/.codex`・`~/.copilot`・
`~/.config/gh` はどの値でも volume に載る。`gh` には CLI 導入や設定テンプレートに対応する
オプションが無い（devcontainer のベースイメージや他 feature で入っている前提で、
`gh auth login` の資格情報だけを持続化する）。オプションが決めるのはそれ以外の agent の
CLI を入れるかどうかと設定を当てるかどうかだけ。

**herdr はこの永続化の対象外。** ログインのような失うと困る状態が無く、設定も既定値のまま
配る方針なので、他の 4 つと違い volume 化していない。`herdr` オプションが決めるのは CLI の
導入と `~/.config/herdr/config.toml` の配置のみで、コンテナを作り直すとその config.toml は
リポジトリの既定値に戻る。

**graphify も CLI 本体は herdr と同じく volume の対象外**（`~/.local/` に入るので
イメージ側に焼ける）。ただし `graphify install --platform <name>` が書き込む先
（`~/.claude/skills/`・`~/.codex/`・`~/.copilot/` 配下）はどれも volume の中なので、
CLI 本体とは別のタイミングで扱う。CLI 本体は `install.sh`（ビルド時）で `uv tool install`
により入れ、スキル登録は volume マウント後の `ensure-skills.sh`（postCreate）で
`claude`/`codex`/`copilot` のうち有効なものごとに行う。`graphify install` は
ネットワーク不要のファイル配置のみで、上書きが通常の動作なので、コンテナを作り直す
たびに再実行しても問題ない。

## しくみ

```
volume "agent-state"
   └─ mount → /var/lib/agent-state
                ├─ claude/
                │    ├─ (ディレクトリ本体)  ←── symlink ── $HOME/.claude
                │    └─ .claude.json        ←── symlink ── $HOME/.claude.json
                ├─ codex/    ←── symlink ── $HOME/.codex
                ├─ copilot/  ←── symlink ── $HOME/.copilot
                └─ gh/       ←── symlink ── $HOME/.config/gh
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

`gh` だけは `$HOME/.<name>` パターンに乗らない。`gh auth login` の資格情報は
`~/.config/gh/hosts.yml` に、それ以外の設定は同じディレクトリの `config.yml` に入るので、
`install.sh` は `gh` だけホームからの相対パスを `.config/gh` に上書きしてから symlink する
（`HOME_REL` 連想配列）。エージェントが増えて同じように `~/.<name>` に収まらない場合は、
ここに 1 行足すだけで対応できる。

所有権は実行時に直しているのではなく、**空の volume がマウント先の所有権を継承する**性質を
使っている。ビルド時に `/var/lib/agent-state` を remote user 所有で作っておけば、初回
マウント時にその所有権ごと volume にコピーアップされるので、sudo 無しで書ける状態から始まる。

## 3 つの実行タイミング

やることによって走る場所が違う。どれも理由がある。

| いつ | 何を | なぜそこか |
| --- | --- | --- |
| **ビルド時** `install.sh` (root) | volume のマウント先を用意、symlink（`~/.claude` `~/.codex` `~/.copilot` `~/.claude.json` `~/.config/gh`）、Claude Code / Copilot / herdr / Graphify の CLI、設定テンプレートと statusline スクリプトの配置、herdr の config.toml | コピーアップに乗せるにはビルド時でないといけない。Claude Code・Copilot・herdr・Graphify はどれも `~/.local/` に入る（volume の外）のでイメージに焼ける |
| **起動ごと** `entrypoint.sh` (root) | 所有権の補正、claude/settings.json と copilot/settings.json へのテンプレートマージ、keybindings.json の symlink | どちらも volume の中。ビルド時に書くとコピーアップが起きる初回にしか届かない |
| **作成後** `ensure-codex.sh` (remote user) | Codex CLI | 下記 |
| **作成後** `ensure-skills.sh` (remote user、`ensure-codex.sh` の後) | lean / luna-shunt の marketplace 追加とインストール、有効な `claude`/`codex`/`copilot` への Graphify スキル登録 | プラグインとスキルは `~/.claude/`・`~/.codex/`・`~/.copilot/` 配下(いずれも volume の中)へ書き込むため、CLI 本体と同じく volume マウント後でないと書けない |

### Codex だけ扱いが違う理由

4 つのうち Codex だけが postCreate なのは、インストーラの置き先が違うから。Claude Code・
Copilot・herdr はどれも `~/.local/`（と Copilot は `~/.cache/copilot/`）に入る。volume の
外なのでイメージに焼ける。postCreate にすると、コンテナを作り直すたびに数百 MB のダウンロードが
走ることになる。

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
settings.json のマージの両方で要る）。

**Copilot の `~/.copilot/settings.json` もまったく同じ扱い**（`entrypoint.sh` の
`apply_json_config` を両者で共有している）。Copilot も `/model` `/theme` `/vim` や
`/settings` で自分で settings.json に書き戻す生きた設定なので、Codex の
「無いときだけ置く」ではなく Claude 側の毎起動マージに寄せている。JSON なので jq が
そのまま使える。違いは `refreshInterval` を付けないことだけで、理由は後述。

`~/.copilot/config.json` には触れない。あちらは CLI が自動管理する内部状態専用
（認証情報やプラグインメタデータなど）で、公式ドキュメントも「通常このファイルを編集する
必要はない」と明記している。ユーザー設定はもともと config.json に書く仕様だったが、
2026-06-11 の Copilot CLI アップデート（`/settings` への統合）で settings.json に移った。
以前の設計のまま config.json にユーザー設定をマージし続けていたところ、有効化した
Copilot CLI がエラーになる不具合が実機で見つかり、settings.json 側に切り替えた。

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
NORMAL · claude-opus-5 · high · fast off · ctx 8%               ← vim モード / モデル ID / effort / fast / コンテキスト
5h: ████████░░ 76% (4h00m)   7d: ██░░░░░░░░ 21% (3d00h)   in 8.5k out 1.2k
                                                            ↑ レート制限（残り） / トークン
● webapp   ◐ dotfiles/my-worktree   ✓ api                       ← 他セッションの状態（居るときだけ）
```

レート制限は**残り使用率**（`100 - used_percentage`）を 10 マスのバー（`█`/`░`）と数値で出す。
減っていく表示にしたいので、使った分ではなく残り分を主役にしている。バーと数値の色は
**経過ぶんの線形ペース**との比較で決まる（`used_percentage` 側で判定するのは変えていない）。
5 時間窓なら 1 時間あたり 20% が等速なので、2 時間経過して使用率が 40% を超えていれば赤、
30%（0.5 時間ぶん手前）を超えていれば黄色。3 時間経過なら赤 60% / 黄 50%。7 日窓も同じ考え方を
日単位で適用する。

コンテキストは 90% 以上で赤、70% 以上で黄色。存在しないフィールドは `--` になる
（vim モード無効、effort 非対応モデル、最初の API 応答前など）。

`in`/`out` は `context_window.total_input_tokens`/`total_output_tokens`。**セッション累計ではなく
現在のコンテキストウィンドウに乗っているトークン数**で、`/compact` や `/clear` で減る・リセットされる。

### 他セッションの状態表示 (agent-status)

同じマシン上で複数の Claude Code セッション（tmux の別ペイン等）を並行して動かしているとき、
自分以外のセッションが「処理中／入力待ち／完了／エラー」のどれかを、名前つき・色つきで
3 行目に出す。[issue #91870](https://github.com/anthropics/claude-code/issues/91870) で
提案されている実験的な Function Hooks（`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS`）は未公開・
未ドキュメントで API も流動的なため使わず、既存の（ドキュメント化済みの）hooks と
statusLine だけで組んでいる。

しくみは書き手と読み手に分かれる。

- **書き手** [`claude/agent-status.sh`](../../../claude/agent-status.sh)。`settings.json`
  の `hooks` から `SessionStart`・`UserPromptSubmit`・`PostToolUse`（失敗時含む）・
  `Stop`・`StopFailure`・`Notification`・`SessionEnd` にぶら下げてある（全部
  `async: true` — 状態を書くだけで許可判定などはしないので、ユーザー操作をブロックする
  理由が無い）。stdin の `hook_event_name`（`Notification` はさらに `notification_type`）
  を見て `~/.claude/agent-status/<session_id>.json` に 1 セッション 1 ファイルで
  `{name, name_rank, cwd, state, updated_at}` を書く。`state` は
  `processing`（`UserPromptSubmit`/`PostToolUse`）・`waiting_input`
  （`Stop`、または `Notification` の `permission_prompt`/`idle_prompt`/`agent_needs_input`）・
  `done`（`SessionEnd`）・`error`（`StopFailure`）の 4 種類。

  `name` は 3 段階の優先度（`name_rank`）で決め、hook が呼ばれるたびに低い rank へ
  後退させることはしない（既存ファイルの rank 以上でしか上書きしない）:
  1. **rank 1: `cwd` ベース。** `.claude/worktrees/<name>` 配下なら worktree 名だけだと
     どのリポジトリか分からないため `リポジトリ名/worktree名`（例: `dotfiles/my-worktree`）、
     それ以外は `cwd` の basename。ファイルがまだ無いとき(`SessionStart` 直後)の初期値。
  2. **rank 2: 最初の指示文の冒頭。** `transcript_path` の `.jsonl` から最初のユーザー
     発言（サブエージェントの会話は除く）を読んで先頭 24 文字を使う。`UserPromptSubmit`
     の時点で transcript に記録されているので、これ以降の hook で rank 1 から上がる。
  3. **rank 3: `session_name`（`--name`/`/rename` や AI 生成タイトル）。** hooks の JSON
     には来ない（statusLine の JSON にしか無い）フィールドなので、`agent-status.sh` では
     設定できない。`claude/statusline-command.sh` 側が自分の `session_name` を検知した
     ときに rank 3 として書き込む。

  rank を分けている理由は、`Stop`/`SessionEnd` のたびに `name` を作り直すと、途中で
  ついたタイトルが消えて `cwd` 表示に戻ってしまう（`done` になった瞬間に限って
  タイトルが消える、という分かりづらい挙動になる）ため。AI 生成タイトルは日本語で
  指示しても英語 3〜5 単語程度になる傾向があり、日本語のまま出したい場合は rank 2
  （最初の指示文の冒頭）のほうが有効なことが多い。
- **読み手** `claude/statusline-command.sh` の末尾。まず自分自身の `session_name` が
  取れていれば、自分の `~/.claude/agent-status/<自分の session_id>.json` を rank 3
  として上書きする（前述の通り hooks からは書けない情報のため、ここでしか書けない）。
  そのうえで `~/.claude/agent-status/*.json` を
  舐めて自分の `session_id` を除外し、`state` ごとに色つきの記号（`●`/`◐`/`✓`/`✗`）を
  `name` の前に振って 1 行にまとめる（processing=シアン `●`、waiting_input=黄色 `◐`、
  done=緑 `✓`、error=赤 `✗`）。色と記号を両方変えているのは色だけだと色覚特性によっては
  区別しづらいため。他セッションが 1 つも居なければ行ごと出さない。
  `updated_at` から 15 分以上更新が無いものは、端末を kill する等で
  `SessionEnd` が発火せず残ったゴミとみなして読み手側が削除する。`done` はセッション終了が
  見えた証拠として 60 秒だけ残してから同様に削除する（即消すと「完了した」の一瞬が見えない）。

同一マシン内のセッション同士が `~/.claude/` を共有していることに依存する。Claude Code
Remote 経由のクラウドセッションは別コンテナで動き、この `~/.claude/` を共有しないため
**今のところ対象外**（あちらの状態を取るなら制御プレーン API を統合する別実装が要る）。

**devcontainer 版 (`features/`) にも反映済み。** `agent-status.sh` を
`statusline-command.sh` と同じ扱いにした:`assets.tsv` に追記して
`features/src/macha-features/claude/agent-status.sh` へ同期し、`install.sh` が
`$SHARE/claude-agent-status.sh` としてイメージ側に配置する。`claude/settings.json`
テンプレート側の `hooks.*.*.hooks[].command` はホスト向けの `~/.claude/agent-status.sh`
を書いているため（`statusLine.command` が `~/.claude/statusline-command.sh` を書いているのと
同じ理由）、`lib/settings.sh` の `apply_json_config` に 5 番目の引数
（`$SHARE/claude-agent-status.sh`）を足し、マージ後に `~/.claude/agent-status.sh` を
指しているコマンドだけ `$SHARE` 側のパスへ jq で書き換えるようにした。Copilot 側の呼び出しは
5 番目の引数を渡さない（空文字扱い）ので、この書き換えは走らない。

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

Claude 版も他セッション表示（居るときだけの動的な行）を除けば 2 行なので、行数自体は揃っている。

| Claude 版 | Copilot 版 |
| --- | --- |
| 1 行目 vim モード / モデル / effort / fast / ctx | モデル / **allow-all** / ctx。`vim.mode` に相当するものは渡らず（`editorMode: "vim"` 自体は効く）、effort と fast mode も渡らないので、代わりに `allow_all_enabled`（全許可モードかどうか）を出している |
| 2 行目 レート制限 5h / 7d | 消費（AI クレジットと premium リクエスト）。窓ごとの上限も reset 時刻も渡らないため、ペース比較も色分けもできず値をそのまま出す |

`refreshInterval` を付けていないのはこの 2 行目のため。Claude 側はレート制限の残り時間を
進める必要があるが、Copilot 側にはそういう放っておくと古くなる表示が無いので、イベント駆動の
ままでよい。コンテキスト率の色（90% 以上で赤、70% 以上で黄色）は Claude 版と揃えている。

## Copilot の settings.json

正は**リポジトリルートの [`copilot/settings.json`](../../../copilot/)** で、
`claude/settings.json` と対になる内容にしている。対応表と、対応するものが無いキーの一覧は
[`install.d/copilot.sh`](../../../install.d/copilot.sh) の頭に置いてある（settings.json は
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

上表のキー名は config.json 時代の設計に基づくもので、settings.json への移行後のスキーマで
そのまま通ることは実機で未検証。有効化してもまだ Copilot CLI がエラーになるようなら、
CLI 上で `/settings` を開いて現在の実際のキー名を確認し、ここと
[`copilot/settings.json`](../../../copilot/) を合わせること。

CLI のインストールは remote user で走らせている。Claude Code と同じく、失敗すると
ビルドが落ちる。`curl | bash` にせず一度ファイルへ落としてから実行しているのは
`ensure-codex.sh` と同じ理由（[Codex だけ扱いが違う理由](#codex-だけ扱いが違う理由)参照）。
`curl ... | bash </dev/null` のようにパイプの最後へ直接リダイレクトを付けると、
リダイレクトはパイプ接続より優先されるため、bash は curl の出力ではなく `/dev/null`
を読むことになりインストーラを一切実行しない。curl 側も書き込み先を読む相手が
いなくなって失敗する（実測: `curl: (23) Failure writing output to destination`。
CI で実際に踏んだ）。

## lean / luna-shunt / copilot plugin

`claudeSkills`・`codexSkills`・`copilotSkills` は「入れるか入れないか」の
一つの switch で、「何を」インストールするかは持たない。中身は
[`claude-skills.json`](./claude-skills.json)・
[`codex-skills.json`](./codex-skills.json)・
[`copilot-skills.json`](./copilot-skills.json) というカタログに分けて
持たせている。`claudeSkills: true` はこのカタログに載っている Claude Code
plugin を**全部**入れる、という意味になる。

```json
// claude-skills.json
[
  {
    "name": "lean",
    "repo": "macha434/lean",
    "marketplace": "macha434-plugins"
  }
]
```

各エントリは `name`(`plugin install <name>@<marketplace>` の名前)・
`repo`(`plugin marketplace add` に渡す `owner/repo`)・
`marketplace`(そのリポジトリの marketplace.json が自称する名前)の3つを
持つ。特定のリポジトリ命名規則には依存しないので、macha434 以外が
作ったプラグインもそのまま同じカタログに並べられる。

プラグインを増やすときはこのカタログにエントリを1つ足すだけでよい。
`devcontainer-feature.json` の options は触らないので、既に
`claudeSkills: true` にしている側は何もしなくても次に作り直した
コンテナから新しいプラグインが入る。`copilot-skills.json` は今のところ
`[]`(対応する Copilot plugin がまだ無い)。

`ensure-skills.sh` は claude/codex については `plugin list --json` で、
copilot については(`--json` 非対応のため)`~/.copilot/installed-plugins/
<marketplace>/<name>` の実在チェックで、既にインストール済みかどうかを
先に見てから `marketplace add` → `install` を行う。config.toml と同じ
「無いときだけやる」方式で、コンテナを作り直すたびに同じネットワーク
越しの処理を繰り返さない。

**Copilot 向けに新しいプラグインを追加する場合の注意:** Copilot の
`marketplace.json` は Claude/Codex とスキーマが違う(`owner` がオブジェクト
必須、`plugins[].source` は相対パスの文字列直書き)。lean/luna-shunt
の `.claude-plugin/marketplace.json` をそのまま流用できないので、
Copilot 向けの marketplace.json は別途用意すること(実機で検証済み)。

## 運用

- **リセット**: `docker volume rm agent-state`。所有権の継承は volume が空のときにしか
  起きないので、feature を直しても既存 volume は直らない
- **同時起動**: 複数コンテナを並行して立てると同じ状態に書く
- **`docker volume prune` では消えない**: 名前付き volume は `-a` を付けたときだけ対象

詳細な設計判断と検証手順は [docs/agent-state-feature-plan.md](../../../docs/agent-state-feature-plan.md) にある。
