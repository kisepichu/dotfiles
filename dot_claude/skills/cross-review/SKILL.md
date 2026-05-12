---
name: cross-review
description: コードレビューを行う。必要に応じて Codex にも依頼する。「レビューして」「コードレビュー」などのリクエストで使用。
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(codex:*)
---

# クロスレビュースキル

まず自分でコードレビューを行い、必要なら Codex にも独立レビューを依頼する。

## レビュー観点

1. 仕様との整合性
2. コーディング規約の遵守
3. 可読性
4. バグの可能性
5. パフォーマンス
6. セキュリティ
7. テスト

## 手順

1. `git diff`, `git log`, 仕様書、プロジェクトルールを読む。
2. findings-first の形式で、自分のレビュー結果をまとめる。
3. 必要なら `codex exec` で独立レビューを依頼する。
   - 例: `codex exec "/review diff --base dev" --output-last-message tmp/codex-review-0.txt`
   - 対象が未コミット差分なら、指示を uncommitted diff に変更する。
4. Codex の指摘を精査し、妥当なものだけ採用する。
5. 修正したら再度レビューし、本質的な指摘がなくなるまで繰り返す。

## 注意

- レビューでは、要約より先に重大度順の指摘を出す。
- 根拠となるファイルと行を示す。
- 修正を行う場合は、ユーザーがレビューだけを求めていないか確認する。
