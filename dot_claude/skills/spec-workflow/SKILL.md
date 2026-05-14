---
name: spec-workflow
description: 仕様駆動の作業フローを進める。Claude Code の spec-do/spec-review/spec-update 相当を Codex で実行したいとき、「spec-do」「spec-review」「spec-update」「仕様からタスク化」「仕様と実装を照合」「docs/plan.md に沿って進める」などの依頼で使用。
metadata:
  short-description: 仕様駆動ワークフロー
---

# Spec Workflow

Claude Code の slash command として運用していた `spec-do`, `spec-review`, `spec-update` を、Codex の skill として実行する。

## モード判定

- `spec-do`, 「仕様から進める」「タスク化して着手」: Do
- `spec-review`, 「仕様と照合」「レビューして同期」: Review
- `spec-update`, 「仕様を更新」「仕様を作る」: Update
- 明示がなければ、ユーザーの依頼に一番近いモードを選ぶ。

## 共通ルール

- 最初に `AGENTS.md`, `CLAUDE.md`, `docs/plan.md`, `docs/spec.md` の有無を確認する。
- 仕様候補は `docs/features/{name}.md`, `docs/commands/{name}.md`, `docs/{name}.md`, `docs/spec.md` の順で探す。
- タスクは `tasks/todo/`, `tasks/doing/`, `tasks/done/` で管理する。
- `TASK-NNN-{name}.md` の NNN は todo/doing/done の最大番号 + 1。
- この repo では、タスク開始時に `develop` から `task-NNN-{name}` 形式のブランチを切る。
- Codex の subagent は、ユーザーが明示的に delegation/parallel agent work を求めた場合だけ使う。通常はローカルに実行する。
- 作業中にチェックリストを作ったら、完了のたびに `[x]` へ更新する。

## Do

1. 対象名を決める。なければ既存 docs から推測し、危険ならユーザーに聞く。
2. 参照仕様とプロジェクトルールを読む。
3. 作業をチェックリストへ分解する。
   - 開発: layer/module/UI/test など、検証単位で切る。
   - 非開発: 調査、判断、作成、検証、公開など、成果物単位で切る。
4. 既存タスクがなければ `tasks/doing/TASK-NNN-{name}.md` を作る。
5. チェックリストを順に実行する。
6. 最後に検証し、必要なら `tasks/done/` へ移動する。

## Review

1. 対象がタスク番号なら `tasks/{todo,doing,done}/TASK-{num}-*.md` を探す。
2. タスクの「参照仕様」、または対象名に対応する docs を読む。
3. 仕様と成果物の差異を挙げる。
   - 仕様にあるが未実装、未作成
   - 成果物にあるが仕様にない
   - 挙動、内容、公開範囲、検証方法が違う
4. 明らかな差異は修正する。判断が必要ならユーザーに確認する。
5. タスクファイルがあればチェックリストと作業ログを更新する。

## Update

1. 既存仕様を探して読む。
2. ユーザーの意図、既存実装、関連 docs から変更案を作る。
3. 方向性を左右する不明点だけ確認する。
4. 仕様ファイルを作成または更新する。
5. `docs/spec.md` や `docs/plan.md` と重複する内容があれば同期する。

## Task Template

```markdown
# TASK-{NNN}: {name}

## 参照仕様

- docs/...

## チェックリスト

- [ ] ...

## 完了条件

- [ ] ...

## 作業ログ

- YYYY-MM-DD: 作業開始
```

## Dotfiles Review Focus

- secret, token, private URL, host-specific path が公開 repo に入っていないか。
- template/private config に逃がすべき値が直書きされていないか。
- install script は idempotent か。
- WSL/Linux/macOS など環境分岐が明示されているか。
