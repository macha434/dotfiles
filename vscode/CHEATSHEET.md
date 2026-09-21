# VSCode 自作キーバインド チートシート

`ctrl+a shift+/` で表示。中身は `keybindings.json` / `settings.json` の
自作バインドを手動でまとめたもの。バインドを変更したらこのファイルも
一緒に更新すること（自動生成ではない）。

## プレフィックス早見表

| プレフィックス | 用途 |
| --- | --- |
| `ctrl+a` | ターミナル / エディタグループ / パネル (tmux 風) |
| `ctrl+d` | サイドバー |
| `ctrl+g` | Git |

## Git / SCM (`ctrl+g`)

| キー | 動作 |
| --- | --- |
| `ctrl+g a` | SCM ビューを開き、1件目の差分をプレビュー |
| `ctrl+g b` | ブランチ切り替え (`git.checkout`) |
| `ctrl+g f` | フェッチ |
| `ctrl+g p` | プッシュ |
| `ctrl+g shift+p` | プル |
| `ctrl+g y` | 同期 (sync) |
| `ctrl+g s` | stash |
| `ctrl+g shift+s` | stash pop (最新) |
| `ctrl+g d` | 差分を開く |
| `ctrl+g j` / `ctrl+g k` | エディタ内の変更箇所を次/前へ (要 `editorTextFocus`) |

## SCM ビュー内 1文字キー (vim風、リストにフォーカス中のみ)

| キー | 動作 |
| --- | --- |
| `j` / `down` | 次の変更へ移動 (同時に差分をプレビュー) |
| `k` / `up` | 前の変更へ移動 |
| `a` | stage |
| `shift+a` | 全て stage |
| `u` | unstage |
| `shift+u` | 全て unstage |
| `d` | 破棄 (`git.clean`、確認あり) |
| `c` | コミットメッセージ入力欄へフォーカス |
| `escape` | 入力欄から変更リストへ戻る |
| `s` | stash |
| `shift+s` | stash pop (最新) |

## ターミナル (`ctrl+a`)

| キー | 動作 |
| --- | --- |
| `ctrl+a -` | 新規ターミナル |
| `ctrl+a e` | パネル ⇔ エディタ領域を切り替え |
| `ctrl+a shift+\` | ペイン分割 |
| `ctrl+a h` / `ctrl+a l` | ペイン間移動 |
| `ctrl+a shift+k` / `ctrl+a shift+j` | ターミナル間移動 |
| `ctrl+a x` | ターミナルを閉じる |

### スクロールバック (copy-mode)、`ctrl+a v` で開始

| キー | 動作 |
| --- | --- |
| `escape` / `q` | 抜ける |
| `j` / `k` | 1行スクロール |
| `d` / `u` | 1ページスクロール |
| `g g` / `shift+g` | 先頭 / 末尾へ |
| `n` / `shift+n` | 次/前のコマンド境界へ (shell integration 必須) |
| `shift+j` / `shift+k` | 次/前のコマンドまで選択 |
| `y` | コピーしてモードを抜ける |
| `/` | 検索 |

## エディタグループ (`ctrl+a`)

| キー | 動作 |
| --- | --- |
| `ctrl+a shift+\` | グループ分割 (エディタフォーカス時) |
| `ctrl+a h` / `ctrl+a l` | グループ間フォーカス移動 |
| `ctrl+a shift+h` / `ctrl+a shift+l` | エディタを隣のグループへ移動 |
| `ctrl+a shift+j` / `ctrl+a shift+k` | グループ内タブを次/前へ |

## パネル (`ctrl+a`)

| キー | 動作 |
| --- | --- |
| `ctrl+a j` / `ctrl+a k` | トグル (非表示/フォーカス中) or フォーカス (表示中) |
| `ctrl+a shift+h` / `ctrl+a shift+l` | パネルのビューを前/次へ切り替え |
| `ctrl+a m` | パネル最大化トグル |
| `ctrl+a o` | 出力チャンネル選択 (Output パネル表示中のみ) |

### 各パネルのフィルタ欄へ

| キー | 動作 |
| --- | --- |
| `/` | 問題パネルのフィルタ欄へ (問題パネル表示中のみ) |
| `/` | デバッグコンソールのフィルタへ (デバッグ REPL 内のみ) |

## サイドバー (`ctrl+d`)

| キー | 動作 |
| --- | --- |
| `ctrl+d f` | エクスプローラを開く |
| `ctrl+d s` | サイドバー ⇔ エディタ を切り替え |
| `ctrl+d b` | 開いているエディタ一覧 ⇔ エクスプローラ を切り替え |
| `ctrl+j` / `ctrl+k` | サイドバーのビュー切り替え (サイドバーフォーカス時) |
| `escape` | サイドバーを閉じる |

## エクスプローラ内 1文字キー (vim風)

| キー | 動作 |
| --- | --- |
| `n` | 新規ファイル |
| `f` | 新規フォルダ |
| `h` / `l` | 圧縮フォルダの前/次へ |
| `r` | 名前変更 |
| `y` | コピー |
| `p` | 貼り付け |
| `d` | 削除 (確認あり) |
| `/` | Quick Open へ |

## リスト / ウィジェットの上下移動

| キー | 動作 |
| --- | --- |
| `ctrl+j` / `ctrl+k` | Quick Pick / サジェスト候補の次/前へ |

## その他

| キー | 動作 |
| --- | --- |
| `ctrl+a ctrl+a` | 全選択 (`ctrl+a` はプレフィックス化したため2打鍵) |
| `ctrl+l` | 副サイドバー (Claude など) のトグル |
| `ctrl+a shift+/` | このチートシートを表示 |

## Vim (VSCodeVim) キーマップ

Normal / Visual モード:

| キー | 動作 |
| --- | --- |
| `J` | `<leader><leader>j` を発火 |
| `K` | `<leader><leader>k` を発火 |
| `W` | `<leader><leader>w` を発火 |
| `E` | `<leader><leader>e` を発火 |
| `B` | `<leader><leader>b` を発火 |

Normal モードのみ:

| キー | 動作 |
| --- | --- |
| `<space>r` | シンボルのリネーム |
| `<space>d` | 定義へジャンプ |
| `<space>t` | 型定義へジャンプ |
| `<space>h` | ホバー表示 |
| `<space>a` | Code Runner 実行 |

Insert モード:

| キー | 動作 |
| --- | --- |
| `jj` | `<Esc>` |
