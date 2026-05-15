# Dotfiles 整理計画

## 目的

- 新 Windows PC + WSL Ubuntu を再現可能にセットアップする。
- 公開してよい dotfiles と agent workflow を GitHub に集約する。
- 秘密情報と環境固有値は公開 repo から分離する。

## 参考方針

- `mizchi/chezmoi-dotfiles` のように、Claude/Codex 用の agent assets も chezmoi で管理する。
- ただし Codex は `~/.codex/skills/.system` を持つため、`~/.codex/skills` 全体を symlink せず、共通 skill を個別 symlink する。
- Claude Code の slash command は `dot_claude/commands/` に置き、spec command の導入手順は `spec-setup` skill に分離する。

## 公開するもの

- shell/editor/git などの設定ファイル
- WSL Ubuntu 用 bootstrap と idempotent install scripts
- Claude Code commands/skills
- Codex skills への symlink 定義
- 公開可能な package list と環境別分岐 template

## ツール管理方針

詳細: `docs/tooling-strategy.md`

- ローカルに直接入れて、同じ設定で常用するもの: `fish`, `tmux`, `nvim`, `starship`, `zoxide`
- bootstrap に必要な基礎ツール: apt で入れる `git`, `curl`, `ca-certificates`, `build-essential` と、bootstrap 中に user-local へ入れる `mise`, `chezmoi`, `prek`
- よく使う CLI だが言語・プロジェクトに強く依存しないもの: 原則 `mise` で管理し、必要に応じて `apt` または `nix profile` を検討する
- 言語ランタイム、LSP、formatter、project-specific toolchain: project 側の Docker, devcontainer, `nix develop`, `mise.toml` に寄せる
- Windows GUI tool: Windows 側 bootstrap に分離する。`wezterm` は WSL 内ではなく Windows 側管理を基本にする
- Docker は WSL Ubuntu 内の Docker Engine を必要になった時点で明示 install する。

## 公開しないもの

- API token, SSH private key, GPG private key, password manager vault data
- 会社名、社内 URL、private repository URL
- machine-local username/email/signing key/path の生値

## フェーズ

### Phase 1: Agent workflow の移植

- [x] `docs/plan.md` を作成する。
- [x] Claude Code の `spec-do`, `spec-review`, `spec-update` を汎用 command として整理する。
- [x] spec command setup 用に `spec-setup` skill を作る。
- [x] Codex から共通 skill を個別 symlink できる chezmoi source を作る。
- [x] `prek`/`pre-commit` 互換の hook と `secretlint` を追加する。
- [x] 現在の `~/.codex/skills` に `spec-setup` をインストールする。

### Phase 2: 現行 dotfiles の棚卸し

- [x] 既存の dotfiles と tool config を一覧化する。
- [x] `~/.config/fish`, `~/.config/nvim`, `~/.tmux`, `~/.tmux.conf` から公開可能な設定だけを取り込む。
- [x] 古い `../dotfiles` は丸ごと移植せず、`fish`, `tmux`, `nvim` の必要部分だけ参照する。
- [x] 公開可能、template 化、private 化、破棄に分類する。
- [x] secret scanning 前提で git 履歴に入れる前の検査手順を作る。

### Phase 3: WSL Ubuntu bootstrap

- [x] fresh WSL Ubuntu で bootstrap が通ることを確認する。
- [x] Windows/WSL の人間向け初回手順を `README.md` にまとめる。
- [x] Ubuntu 初回 bootstrap script を作る。
- [x] `apt` package list と third-party repository 設定を idempotent にする。
- [x] `fish`, `tmux`, `nvim` のインストールと default shell 設定を idempotent にする。
- [x] `starship` prompt と `zoxide` の `z` command を user-level tool として有効化する。
- [x] `mise` を入れ、常用 CLI と language runtime の管理境界を決める。
- [x] Nix は optional path として試験導入し、最初から必須 bootstrap にしない。
- [ ] `chezmoi init --apply` までの最短経路を確認する。通常の `chezmoi apply` は managed `chezmoi.toml` で `~/repos/chezmoi-dotfiles` を default source にする方針まで反映済み。
- [x] Docker は WSL Ubuntu 内 Docker Engine を `scripts/install-docker-engine-wsl.sh` で任意導入する方針にする。

### Phase 4: chezmoi template 化

- [ ] `chezmoi.toml.tmpl` で profile, email, WSL 判定などを入力する。
- [ ] Git identity や host 固有設定を template/private config に逃がす。
- [ ] OS/profile ごとに `.chezmoiignore` または template 条件分岐を整える。

### Phase 5: 検証

- [x] fresh WSL Ubuntu で bootstrap を確認する。2026-05-15 時点で fresh WSL での動作確認済み。
- [ ] `chezmoi diff` と `chezmoi apply` を確認する。bootstrap 中の `chezmoi` 呼び出し、default source、`mise` config 変更後の `starship`/`zoxide` install 再実行は修正済み。
- [ ] `gitleaks` か同等の secret scan を通す。

## 現在の状態

詳細: `docs/current-state.md`

- `fish`, `tmux`, `nvim`, `mise`, `starship`, `zoxide`, agent workflow は chezmoi source に取り込み済み。
- `scripts/bootstrap-wsl-ubuntu.sh` は repo 外の作業場所から実行しても `~/repos/chezmoi-dotfiles` を default source として使えるようにする。
- `run_onchange_after_40-mise-install.sh.tmpl` は `dot_config/mise/config.toml` の変更で再実行されるため、後から追加した `starship`/`zoxide` も `chezmoi apply` で install 対象になる。
- 次の大きな作業は、`chezmoi init --apply` 導線の確認、Docker Engine を bootstrap に含めるかの判断、追加の secret scan 導入検討を進めること。
