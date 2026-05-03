# Tooling Strategy

## 目的

新 PC の WSL Ubuntu で、必要な道具はすぐ使えるようにしつつ、言語やプロジェクト固有の依存でローカル環境を汚さない。

## 分類

### System bootstrap

最小限の OS package と bootstrap に必要な道具だけを `apt` で入れる。

- `git`
- `curl`
- `ca-certificates`
- `build-essential`
- `fish`
- `tmux`
- `chezmoi`

理由:

- shell/editor/multiplexer はログイン直後から使うため、project dev shell に依存させない。
- `fish`, `tmux`, `nvim` は設定ファイルもこの repo で管理する。
- `apt` は Ubuntu/WSL の土台として最も壊れにくい。
- `neovim` は Ubuntu LTS の apt 版が古くなりやすいため、binary は `mise` 管理にする。

### User-level common tools

プロジェクトをまたいで常用する CLI は `mise` を第一候補にする。

- `node`, `pnpm`, `go`, `rust`, `python`, `ruby` などの runtime
- `neovim`
- `prek`
- `chezmoi` の pinned version
- その他、mise backend で自然に扱える CLI

理由:

- user-local に閉じる。
- version pin がしやすい。
- project ごとの `.mise.toml` に切り替えやすい。

### Project-specific development

言語・プロジェクトに強く依存するものはローカルに直接入れない。

- Docker / devcontainer
- `nix develop`
- project-local `.mise.toml`
- repository-local package manager lockfile

例:

- 特定プロジェクト用の DB, Redis, browser automation dependencies
- project 固有の LSP, formatter, compiler version
- 一時的な検証用 toolchain

### Windows-side tools

Windows GUI tool は WSL とは別に扱う。

- `WezTerm`
- browser
- VS Code / Cursor
- PowerToys
- Windows Terminal settings

`wezterm` は Windows 側に入れ、設定だけを別 phase で管理する。WSL 内 bootstrap の必須項目にはしない。

## Nix の扱い

今回の結論: Nix は有用だが、最初から dotfiles bootstrap の必須基盤にしない。まず optional にする。

### 向いている用途

- project ごとの reproducible development shell
- `nix develop` で一時的な toolchain を使う
- Docker image ほど重くないが、ローカルを汚したくない開発環境
- Linux/macOS/WSL をまたいだ共通 CLI 環境の実験

### 今回は慎重にする理由

- Nix language, flakes, Home Manager まで入れると学習・保守コストが上がる。
- `chezmoi` と Home Manager はどちらも dotfiles を管理できるため、責務が重なる。
- WSL の初回 bootstrap で Nix を必須にすると、失敗時の切り分けが増える。
- shell/editor の初期復旧は `apt` + `chezmoi` のほうが単純。

### 採用ライン

1. Phase 3 では Nix を optional install にする。
2. Phase 4 以降で `nix develop` 用の最小 `flake.nix` を試す。
3. Home Manager はすぐには使わない。chezmoi 管理が辛くなった場合だけ検討する。
4. Nix が安定して便利なら、常用 CLI の一部を `nix profile` または Home Manager に移す。

### WSL でのインストール方針

- systemd enabled WSL なら official Nix の multi-user install を候補にする。
- systemd なし WSL なら official Nix の single-user install を候補にする。
- Determinate Nix Installer は WSL 対応で rollback/uninstall が分かりやすいため、実験環境では候補にする。

## 取り込み対象

### fish

- `~/.config/fish/config.fish`
- `~/.config/fish/fish_plugins`
- 必要な `conf.d/*.fish`
- 必要な `functions/*.fish`

除外:

- `fish_variables` は machine-local 状態を含みやすいので原則取り込まない。

### tmux

- `~/.tmux.conf`
- `~/.tmux/` の自作 script

除外:

- build artifacts
- clone 済み tmux source tree

### nvim

- `~/.config/nvim/init.lua`
- `~/.config/nvim/lua/`
- `~/.config/nvim/lazyvim.json`
- `~/.config/nvim/stylua.toml`

注意:

- `lazy-lock.json` は再現性を優先するなら管理する。更新頻度が高くうるさければ後で方針変更する。
- plugin cache, generated files, local workspace config は入れない。

## 古い dotfiles の扱い

`../dotfiles` は参考にするが、丸ごと移植しない。

特に以下は公開 repo に入れない。

- browser state
- `gh/hosts.yml`
- token files
- private key / certificate
- history / cache / local database
- service-specific generated config
