# TASK-001: core tools import

## 参照仕様

- docs/plan.md
- docs/tooling-strategy.md
- docs/dotfiles-inventory.md

## チェックリスト

- [x] 現行 `fish`, `tmux`, `nvim` 設定を一覧化する。
- [x] 公開 repo に入れないファイルと machine-local な値を分類する。
- [x] `~/.bashrc`, `~/.bash_profile`, `~/.profile` を確認し、fish に統合する候補を分類する。
- [ ] bash startup files 由来の PATH/alias/env を fish config に整理する。
- [ ] `tmux` 設定を chezmoi source に取り込む。
- [ ] TPM install を idempotent な script にする。
- [ ] `fish` 設定を private/machine-local 部分を除いて取り込む。
- [ ] `nvim` 設定を不要 sample と local state を除いて取り込む。
- [ ] bootstrap package list に `fish`, `tmux`, `neovim` と必要な補助 tool を反映する。
- [ ] `chezmoi --source . diff` と `prek run --all-files` を通す。

## 完了条件

- [ ] 新規 WSL Ubuntu で `fish`, `tmux`, `nvim` がインストール可能な bootstrap 方針がある。
- [ ] public repo に secret, token, private key, machine-local state が入っていない。
- [ ] 常用設定が chezmoi source として管理されている。

## 作業ログ

- 2026-05-02: Phase 2 の棚卸しを開始。現行 `fish`, `tmux`, `nvim` のファイル一覧と取り込み方針を記録。
- 2026-05-02: `~/.bashrc`, `~/.bash_profile`, `~/.profile` を確認。fish へ移すもの、project/mise/Docker/Nix 側へ逃がすものを分類。
