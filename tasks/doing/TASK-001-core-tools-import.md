# TASK-001: core tools import

## 参照仕様

- docs/plan.md
- docs/tooling-strategy.md
- docs/dotfiles-inventory.md

## チェックリスト

- [x] 現行 `fish`, `tmux`, `nvim` 設定を一覧化する。
- [x] 公開 repo に入れないファイルと machine-local な値を分類する。
- [x] `~/.bashrc`, `~/.bash_profile`, `~/.profile` を確認し、fish に統合する候補を分類する。
- [x] bash startup files 由来の PATH/alias/env を fish config に整理する。
- [x] `tmux` 設定を chezmoi source に取り込む。
- [x] TPM install を idempotent な script にする。
- [x] `fish` 設定を private/machine-local 部分を除いて取り込む。
- [x] `nvim` 設定を不要 sample と local state を除いて取り込む。
- [x] bootstrap package list に `fish`, `tmux`, `neovim` と必要な補助 tool を反映する。
- [ ] `chezmoi --source . diff` と `prek run --all-files` を通す。

## 完了条件

- [ ] 新規 WSL Ubuntu で `fish`, `tmux`, `nvim` がインストール可能な bootstrap 方針がある。
- [ ] public repo に secret, token, private key, machine-local state が入っていない。
- [ ] 常用設定が chezmoi source として管理されている。

## 作業ログ

- 2026-05-02: Phase 2 の棚卸しを開始。現行 `fish`, `tmux`, `nvim` のファイル一覧と取り込み方針を記録。
- 2026-05-02: `~/.bashrc`, `~/.bash_profile`, `~/.profile` を確認。fish へ移すもの、project/mise/Docker/Nix 側へ逃がすものを分類。
- 2026-05-02: `tmux` 設定を chezmoi source に取り込み。TPM は repo に vendor せず `run_once` script で clone する方針にした。
- 2026-05-02: `fish` 設定を `~/.bashrc` 由来の常用 alias/env と合わせて整理。private daemon 起動、project 固有 alias、debug env は除外。
- 2026-05-02: `nvim` 設定を chezmoi source に取り込み。LazyVim sample の `example.lua` と local state は除外。
- 2026-05-02: Ubuntu apt bootstrap, mise install, mise tool install scripts を追加。`fish`/`tmux` は apt、`neovim` は mise 管理にした。
