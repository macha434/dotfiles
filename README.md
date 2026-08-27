# dotfiles

Personal configuration files, with an installer that detects the OS and places each file at the tool's default location.

[日本語版 README](README.ja.md)

## Overview

- Target users: myself, on every machine I work from
- Problem solved: the same editor configuration has to be reproduced by hand on each machine, and its path differs per OS
- Value: one command places everything at the right path, and each tool lives in its own installer file so new ones can be added without touching the entry point

## Key Features

- Detects Linux, WSL, macOS and Git Bash on Windows, and resolves each tool's default config directory
- Symlinks on Linux and macOS, copies for Windows destinations. The choice is made per destination path, so a WSL run can do both
- One installer per tool under `install.d/`, picked up automatically by `install.sh`
- Backs up what was already there, once, as `<file>.dotfiles.bak`
- Re-runnable. Unchanged files are skipped, and line endings alone are not treated as a change

## Tech Stack

- Language: Bash
- Covered tools: Visual Studio Code (`settings.json`, `keybindings.json`)

## Setup

```bash
git clone https://github.com/macha434/dotfiles.git
cd dotfiles
./install.sh --dry-run
./install.sh
```

`--dry-run` prints every destination without writing anything. Run it first to confirm the detected OS and paths are what you expect.

## Usage

`install.sh` is the only entry point.

```bash
./install.sh              # install everything
./install.sh vscode       # install only the named tools
./install.sh --dry-run    # print what would happen, write nothing
./install.sh --list       # list installable tools
./install.sh --help       # show usage
```

Where files are placed:

| OS | Destination | Method |
| --- | --- | --- |
| Linux | `${XDG_CONFIG_HOME:-~/.config}/Code/User/` | symlink |
| macOS | `~/Library/Application Support/Code/User/` | symlink |
| Windows (Git Bash, MSYS2) | `%APPDATA%/Code/User/` | copy |
| WSL | Windows-side `%APPDATA%/Code/User/` | copy |

A symlink created from WSL under `/mnt` cannot be followed by Windows applications, so those destinations are copied instead. This means a WSL install is one-way: after editing a file in this repository, run `./install.sh` again.

On WSL only the Windows-side path is used. `~/.config/Code` can exist without VS Code being installed on the Linux side, so its presence is not used to decide.

Environment variables:

| Variable | Effect |
| --- | --- |
| `DOTFILES_OS` | Skip detection and force `linux`, `wsl`, `macos` or `windows` |
| `DOTFILES_WIN_APPDATA` | Path to use as `%APPDATA%` when it cannot be resolved automatically |
| `DOTFILES_VSCODE_LINUX=1` | On WSL, also install to the Linux-side VS Code directory |

## Development

Check that every script parses:

```bash
for f in install.sh lib/common.sh install.d/*.sh; do bash -n "$f"; done
```

Layout:

| Path | Role |
| --- | --- |
| `install.sh` | Entry point. Parses arguments and runs each `install.d/*.sh` in a subshell |
| `lib/common.sh` | OS detection, Windows path resolution, `install_file`, logging |
| `install.d/<name>.sh` | Installs one tool. The file name is the name accepted on the command line |
| `vscode/` | The files themselves |

To add a tool, drop its files in a directory and add `install.d/<name>.sh`. `install.sh` finds it by glob, so the entry point needs no change. Inside the script, `$DOTFILES_ROOT` points at the repository root, `$DOTFILES_OS` holds the detected OS, and `install_file <src> <dest>` handles backup, symlink or copy, and `--dry-run`.

## FAQ

**Q. Why does `settings.json` get rewritten every time on a Windows destination?**  
A. Extensions write to it. VSCodeVim with `vim.statusBarColorControl` enabled adds `workbench.colorCustomizations` as you switch modes, so the installed file diverges from this repository. The installer overwrites it, and the backup is taken only on the first run so backups do not pile up.

**Q. Can it run from PowerShell?**  
A. Not yet. `install.sh` covers Linux, macOS, WSL and Git Bash.

## License

No license file is present.
