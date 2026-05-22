# TASK-006: macos-initial-setup

## 参照仕様

- AGENTS.md
- docs/plan.md
- docs/tooling-strategy.md

## チェックリスト

- [x] Windows から macOS へ移る人向けのキーボード・初期設定事例を Web で確認する。
- [x] macOS 専用の初期設定 bootstrap を追加する。
- [x] Windows 寄せの Karabiner-Elements 設定を chezmoi 管理へ追加する。
- [x] macOS 初期設定手順を Markdown にまとめる。
- [x] WSL/Linux 既存 bootstrap を壊していないことを静的に検証する。

## 完了条件

- [x] macOS 用の処理が `.chezmoi.os == "darwin"` に閉じている。
- [x] WSL Ubuntu の既存 `apt`/bootstrap 経路が変更されていない。
- [x] `prek run --all-files` または `pre-commit run --all-files` が通る。

## 作業ログ

- 2026-05-22: 作業開始。Karabiner-Elements と Windows/Linux 風ショートカット事例を調査。
- 2026-05-22: macOS bootstrap、macOS defaults、Karabiner profile、初期設定 docs を追加。
- 2026-05-22: `browse` helper が macOS では `open` を使うように fish config を調整。
- 2026-05-22: Linux/WSL 向け既存 bootstrap に差分がないことを確認し、`prek run --all-files` が通過。
