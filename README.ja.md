# dotfiles

個人用の設定ファイルと、OS を判別して各ツールの既定のパスへ配置するインストーラである。

[English README](README.md)

## 概要

- 対象ユーザー: 自分自身（作業するすべてのマシン）
- 解決する課題: 同じエディタ設定をマシンごとに手で再現する必要があり、置き場所も OS ごとに違う
- 提供価値: コマンド1つで正しいパスへ配置できる。ツールごとにインストーラを分けてあるので、追加してもエントリポイントを触らずに済む

## 主な機能

- Linux / WSL / macOS / Windows（Git Bash）を判別し、各ツールの既定の設定ディレクトリを解決する
- Linux と macOS では symlink、Windows 側の設置先ではコピー。判断は設置先パスごとに行うので、WSL からの実行で両方を扱える
- ツールごとに `install.d/` へ1ファイル置くだけで、`install.sh` が自動で拾う
- 元からあったファイルを初回だけ `<ファイル名>.dotfiles.bak` として退避する
- 繰り返し実行できる。差分の無いファイルはスキップし、改行コードだけの違いは変更とみなさない

## 技術スタック

- 言語: Bash
- 対象ツール: Visual Studio Code（`settings.json`、`keybindings.json`）、Claude Code（`settings.json`、`keybindings.json`、`statusline-command.sh`）、Codex CLI（`config.toml`）

## セットアップ

```bash
git clone https://github.com/macha434/dotfiles.git
cd dotfiles
./install.sh --dry-run
./install.sh
```

`--dry-run` は書き込みを行わず、設置先だけを表示する。判別された OS とパスが想定どおりかを先に確認するために使う。

## 使い方

入口は `install.sh` だけである。

```bash
./install.sh              # すべて配置する
./install.sh vscode       # 指定したものだけ配置する
./install.sh --dry-run    # 何をするかだけ表示し、書き込まない
./install.sh --list       # 配置できるものを一覧する
./install.sh --help       # 使い方を表示する
```

配置先:

| OS | 設置先 | 方式 |
| --- | --- | --- |
| Linux | `${XDG_CONFIG_HOME:-~/.config}/Code/User/` | symlink |
| macOS | `~/Library/Application Support/Code/User/` | symlink |
| Windows（Git Bash、MSYS2） | `%APPDATA%/Code/User/` | コピー |
| WSL | Windows 側の `%APPDATA%/Code/User/` | コピー |

WSL から `/mnt` 以下に張った symlink は Windows のアプリケーションから辿れないため、その設置先はコピーで扱う。したがって WSL でのインストールは一方向であり、このリポジトリのファイルを編集したら `./install.sh` を再実行する必要がある。

WSL では Windows 側のパスにのみ配置する。`~/.config/Code` は Linux 側に VS Code が入っていなくても残っていることがあるため、存在の有無では判定しない。

環境変数:

| 変数 | 効果 |
| --- | --- |
| `DOTFILES_OS` | 判別を行わず `linux` / `wsl` / `macos` / `windows` を強制する |
| `DOTFILES_WIN_APPDATA` | `%APPDATA%` を自動解決できない場合に使うパス |
| `DOTFILES_VSCODE_LINUX=1` | WSL で、Linux 側の VS Code のディレクトリにも配置する |

## 開発

すべてのスクリプトが構文的に正しいかを確認する:

```bash
for f in install.sh lib/common.sh install.d/*.sh; do bash -n "$f"; done
```

構成:

| パス | 役割 |
| --- | --- |
| `install.sh` | エントリポイント。引数を解釈し、各 `install.d/*.sh` を副シェルで実行する |
| `lib/common.sh` | OS 判別、Windows のパス解決、`install_file`、ログ出力 |
| `install.d/<名前>.sh` | ツール1つ分の配置手順。ファイル名がコマンドラインで指定できる名前になる |
| `vscode/` | VS Code の設定ファイルの実体 |
| `claude/` | Claude Code の設定ファイルの実体。`settings.json` とステータスラインのスクリプトを含む |
| `codex/` | Codex CLI の `config.toml`。`claude/settings.json` と対になる内容にしている |
| `features/` | GHCR に publish する devcontainer feature とそのテスト。`install.sh` は関知しない |
| `docs/` | 設計メモと実装プラン |
| `features/assets.tsv` | packaging 前に feature へ複製する dotfiles の対応表 |

ツールを追加するには、ファイルをディレクトリに置き、`install.d/<名前>.sh` を作る。`install.sh` は glob で拾うため、エントリポイント側の変更は不要である。スクリプト内では `$DOTFILES_ROOT` がリポジトリのルート、`$DOTFILES_OS` が判別結果を指し、`install_file <元> <設置先>` が退避・symlink とコピーの使い分け・`--dry-run` を引き受ける。

## よくある質問

**Q. Windows 側の `settings.json` が毎回書き換えられるのはなぜか。**  
A. 拡張機能が書き込むためである。VSCodeVim の `vim.statusBarColorControl` を有効にしていると、モードを切り替えるたびに `workbench.colorCustomizations` が追記され、このリポジトリの内容とズレる。インストーラはこれを上書きする。退避は初回だけ行うので、バックアップが溜まることはない。

**Q. インストーラを再実行すると、Claude Code 自身が `~/.claude/settings.json` に書いた内容（MCP サーバーの承認履歴など）は消えるか。**  
A. 消える。`claude/settings.json` は VS Code の `settings.json` と同じ扱いで、`install_file` がリポジトリ側と差分があれば設置先を上書きする。これが困るなら `install.d/claude.sh` からこの行を外し、`~/.claude/settings.json` は手動管理に切り替えてほしい。

**Q. PowerShell から実行できるか。**  
A. 現時点ではできない。`install.sh` が Linux / macOS / WSL / Git Bash をカバーしている。

## ライセンス

ライセンスファイルは置いていない。
