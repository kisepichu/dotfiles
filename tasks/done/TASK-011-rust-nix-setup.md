# TASK-011: rust-nix-setup

## 参照仕様

- AGENTS.md
- docs/tooling-strategy.md
- ユーザー要望: この mac に rust と nix を入れたい。`mise install rust` を手元でやってしまったので dotfiles 側でも入るようにする。nvim で rust-analyzer 等を使えるようにする。nix のインストール方法を検討して repo に反映する。WSL 用も対応する。

## 調査メモ

- `dot_config/mise/config.toml` には `rust` が未登録。手元の `~/.config/mise/config.toml` には `rust = "latest"` が追加済みで chezmoi diff が出ている。
- mise の rust は rustup 管理 (`RUSTUP_HOME=~/.rustup`, `CARGO_HOME=~/.cargo`, toolchain `1.96.0`)。
- nvim で rust-analyzer が動かない原因: `~/.cargo/bin/rust-analyzer` は rustup proxy だが `rust-analyzer` component が未インストールで実行時にエラー (`Unknown binary 'rust-analyzer'`)。`rust-src` も未インストール（標準ライブラリ補完/定義ジャンプに必要）。
- nvim 側: `lazyvim.plugins.extras.lang.rust` + `rustaceanvim` は既に有効。rust extra は rust-analyzer を rustup 経由 (PATH) で使う設計なので、component を入れれば nvim 設定変更は不要。`firenvim.lua` の mason 無効化は firenvim 起動時のみで通常 nvim には影響しない。
- component 追加は `mise exec rust -- rustup component add rust-analyzer rust-src` が `RUSTUP_TOOLCHAIN` 経由で mise 管理 toolchain を正しく解決することを確認済み（読み取り専用検証）。
- nix: 現状未使用。`docs/tooling-strategy.md` で「optional、core bootstrap には含めない」方針。`scripts/install-docker-engine-wsl.sh` と同じ「明示実行スクリプト」前例あり。
- nix インストール方法はユーザー決定で **Determinate Nix Installer**（mac/WSL 両対応・systemd 検出・uninstall/rollback が容易）。
- 今回の作業範囲はユーザー決定で **リポジトリ更新のみ**（この mac での実インストールは行わない）。

## 方針

- rust 本体は `mise` 管理に揃える（tooling-strategy の User-level common tools 方針と一致、ユーザーの操作とも一致）。
- rust-analyzer / rust-src は chezmoi の `run_onchange_after` で mise install 後に冪等に追加する。mac/WSL 共通。
- nix は core bootstrap に含めず、`scripts/install-nix.sh` の明示実行スクリプト方式（docker の前例に揃える）。Determinate Nix Installer を使い、macOS と WSL(systemd 有無) を検出する。
- README と tooling-strategy に手順・方針を反映する。

## チェックリスト

- [x] `dot_config/mise/config.toml` に `rust = "latest"` を追加。
- [x] `run_onchange_after_45-rust-components.sh.tmpl` を追加（rust-analyzer / rust-src を冪等に追加、mac/WSL 共通、mise/rust 未導入時は graceful skip）。
- [x] `scripts/install-nix.sh` を追加（Determinate Nix Installer、macOS/WSL 対応、systemd 検出、導入済みなら skip）。
- [x] `docs/tooling-strategy.md` の Nix 節を決定事項（Determinate + 明示スクリプト）に更新。
- [x] `README.md` に Nix 手順と rust/rust-analyzer の補足を追記。
- [x] `prek run --all-files`（または `pre-commit run --all-files`）が通る。

## 完了条件

- [x] rust が dotfiles の mise 管理対象になり、`chezmoi apply` で rust-analyzer / rust-src が入る経路がある。
- [x] nix インストール手段が repo にあり、macOS と WSL の両方を扱える。
- [x] mac 固有 / WSL 固有処理が既存の OS 分岐方針を壊していない。
- [x] `prek run --all-files` または `pre-commit run --all-files` が通る。

## 作業ログ

- 2026-05-31: 作業開始。rust/nix まわりの現状調査。rust-analyzer 不動の原因（rustup component 未導入）を特定。nix 方式を Determinate Nix Installer に決定、作業範囲は repo 更新のみと確認。
- 2026-06-01: 実装完了。mise config に rust 追加、`run_onchange_after_45-rust-components.sh.tmpl`、`scripts/install-nix.sh` を追加、docs/README を更新。chezmoi テンプレートのレンダリングと bash 構文、`prek run --all-files` を確認。作業範囲どおり実インストールは未実施。
