# TASK-007: pr-review の Copilot 待ちを Claude Code の background 実行へ移行

## 参照仕様

- User request on 2026-05-29: Claude Code に追加された待ち系機能（Monitor / background tasks / scheduled tasks）の影響で `wait-copilot-review.py` が前景でうまく動かず、agent が並列待ち・ポーリングのような挙動になる。ベストプラクティスを調べ、可能なら統一、無理なら待ちスクリプトの仕組みを Codex 側へ複製して Claude Code 側だけ変える。
- AGENTS.md

## 調査メモ

- 根本原因: `wait-copilot-review.py` は最大15分（90 attempts × 10s）前景ブロッキングするが、新しい Claude Code harness の前景 Bash はデフォルト2分・最大10分でタイムアウトする。タイムアウト後に agent が未完了と誤認して再実行・並列待ちを始めていた。
- ベストプラクティス（Claude Code Monitor / background tools のドキュメント）: 「条件成立を1回だけ通知してほしい」用途は `run_in_background: true` で「条件成立時に exit するコマンド」を起動するのが正。完了時に harness が1回通知して agent を自動再起動するため、ポーリング不要・前景タイムアウト無関係。
- スクリプト本体は既に「ポーリングして条件成立で exit」する設計なので変更不要。前景か background かの呼び方の差だけ。
- Codex は background/通知の仕組みを持たないため、従来どおり前景同期ブロッキングが正しい。

## 方針

- 待ちスクリプト（および pr-review の他スクリプト）は単一ソースのまま共有する。
- Codex の pr-review をディレクトリ symlink から「独自 SKILL.md（同期ブロッキング待ち）＋ scripts を Claude 側へ symlink」に再構成する。
- Claude の SKILL.md の wait 手順だけを `run_in_background` 待ちに変更する。

## チェックリスト

- [x] 待ち系の影響と Claude Code のベストプラクティスを調査する。
- [x] Codex 版 pr-review を `dot_codex/skills/pr-review/`（SKILL.md ＋ scripts symlink）へ再構成し、旧 `symlink_pr-review` を削除する。
- [x] Claude 版 SKILL.md の手順 2・8 を `run_in_background` での待ちに変更する。
- [x] `scripts/check-chezmoi-managed.sh` を新しい Codex 構成に追従させる。
- [x] `scripts/validate-skills.sh` / `chezmoi managed` / `prek run --all-files` 相当の検証を通す。

## 完了条件

- [x] Claude Code 側で wait が background 実行となり、前景タイムアウト由来の並列待ち・再実行が起きない指示になっている。
- [x] Codex 側は従来どおり前景同期で待つ独自 SKILL.md を持ち、scripts は Claude 版と単一ソース共有されている。
- [x] skill validation と chezmoi managed の整合、pre-commit 相当の検証が通っている。

## 作業ログ

- 2026-05-29: 作業開始。`wait-copilot-review.py` の前景ブロッキングと新 harness の Bash タイムアウトが衝突しているのが原因と特定。Monitor / background の公式指針を確認。
- 2026-05-29: 構成方針をユーザーに確認（scripts 共有・SKILL.md だけ分離を採用）。Codex を独自 SKILL.md ＋ `symlink_scripts` に再構成、Claude SKILL.md の手順 2・8 を background 待ちへ変更、`check-chezmoi-managed.sh` を更新。
