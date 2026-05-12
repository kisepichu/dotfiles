# TASK-002: sync local configs

## 参照仕様

- docs/plan.md
- docs/current-state.md
- AGENTS.md

## チェックリスト

- [x] 現 PC の設定ファイル候補を一覧化する。
- [x] 既存の chezmoi source と差分を比較する。
- [x] 公開 repo に入れられるもの、template/private 化するもの、除外するものに分類する。
- [x] ローカル設定が妥当でない場合は、そのまま反映せず改善方針を決めてから取り込む。
- [x] 公開可能な設定を chezmoi source に反映する。
- [x] Claude/Codex の command, skill, workflow 更新を反映する。
- [x] `chezmoi diff` 相当で反映内容を確認する。
- [x] `prek run --all-files` を通す。

## 完了条件

- [x] 現 PC で使っている主要設定が、公開可能な範囲で chezmoi source に反映されている。
- [x] secret, private URL, credentials, machine-local identity values が repo に入っていない。
- [x] 反映しない設定の理由が作業ログまたは関連 docs に残っている。
- [x] PR を `main` 向けに出せる状態になっている。

## 作業ログ

- 2026-05-12: TASK-002 を開始。対象を agent 設定に限定せず、現 PC の設定ファイル全般の同期として扱う。
- 2026-05-12: `~/.claude`, `~/.codex`, fish, mise, nvim, tmux の差分を確認。fish/mise/tmux と nvim の多くは repo 側が新しく妥当なため、ローカル側へ戻さない。
- 2026-05-12: `~/.claude` の credentials, sessions, projects, todos, shell snapshots は private/local state のため除外。`~/.codex/config.toml` と `rules/default.rules` は machine-local path と承認履歴を含むため除外。
- 2026-05-12: nvim の local Lean formatter/Rust DAP は tool binary/backend 管理が未整理のため今回は除外。OSC52 clipboard は汎用設定として `pcall` 付きで反映。
- 2026-05-12: `pr-review` skill の実運用版と scripts、`pr` skill、`review` skill、Codex symlink を反映。`spec-workflow` にこの repo の task branch ルールを短く追記。
- 2026-05-12: `chezmoi diff` で今回対象の反映内容を確認し、`prek run --all-files` 通過。
