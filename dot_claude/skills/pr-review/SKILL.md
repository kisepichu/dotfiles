---
name: pr-review
description: PR についたレビューコメントを取得し、修正・返信・Resolve し、必要なら Copilot に再レビュー依頼して完了までループする。「PR コメント対応して」「レビュー対応」などのリクエストで使用。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git rev-parse HEAD:*), Bash(git rev-parse --short HEAD:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh --version:*), Bash(gh pr view:*), Bash(gh pr edit:*), Bash(python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/get-review-comments.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/reply-review-comment.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/resolve-review-threads.py:*), Bash(cargo:*), Bash(pnpm:*)
---

# PR コメント対応スキル

PR レビューコメント取得、対応、返信、Resolve まで行う。修正を push した場合は Copilot に再レビュー依頼し、Copilot が `generated no comments` / `generated no new comments` の review を返すまで繰り返す。

## 手順

### 1. PR と環境を確認

PR 番号と repo はカレントブランチから取得する。指定があればそれを使う。

```bash
gh pr view --json number,url,headRefOid,reviewRequests,latestReviews
```

```bash
gh --version
```

Copilot 再レビュー依頼には `gh >= 2.88.0` が必要。

### 2. Copilot review を待つ

PR 作成直後など、Copilot の初回 review がまだ無い場合がある。コメント取得前に必ず次を実行する。既存の Copilot review があればその結果を使い、まだ無ければ Copilot に review 依頼して待つ。

```bash
python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py {owner} {repo} {num}
```

exit code 0 かつ `no_comments: true` なら完了。exit code 20 なら Copilot がコメントを生成しているので手順 3 に進む。

### 3. コメント全件取得

```bash
python3 ~/.claude/skills/pr-review/scripts/get-review-comments.py {owner} {repo} {num}
gh pr view {num} -R {owner}/{repo} --json reviews --jq '.reviews'
```

### 4. 未返信コメントを特定する

`in_reply_to_id == null` がスレッド起点。起点コメントのうち、自分の返信 (`in_reply_to_id == 起点コメント id`) がないものを未対応とする。

### 5. 未対応コメントを分類・対応

- 妥当: コードまたは仕様を修正し、チェック系コマンドを実行する。通ったら具体的なファイルだけ `git add` し、`git commit --no-gpg-sign -m "..."`、必要なら `git push` する。
- 今対応不要: 設計意図、スコープ外、既知制限など、今対応するべきでない理由を必ず返信する。
- 質問・確認: ユーザーに判断を仰ぐ。

### 6. 返信

返信本文を `/tmp/pr-review-reply.md` に `Write` してから送る。`$SHA=$(...)` のような代入や command substitution は使わず、必要なら `git rev-parse HEAD` を単独実行して、その結果を本文に文字列として書く。

```bash
python3 ~/.claude/skills/pr-review/scripts/reply-review-comment.py {owner} {repo} {num} {comment_id} /tmp/pr-review-reply.md
```

### 7. 返信済みスレッドのみ Resolve

全未解決を一括 Resolve せず、返信済みスレッドだけ Resolve する。

```bash
python3 ~/.claude/skills/pr-review/scripts/resolve-review-threads.py {owner} {repo} {num} {comment_id}...
```

### 8. push 後に Copilot 再レビュー依頼して待つ

修正を commit / push したら、Copilot に再レビュー依頼して完了まで待つ。

```bash
python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py {owner} {repo} {num} --request
```

exit code 0 かつ `no_comments: true` なら完了。exit code 20 なら Copilot がコメントを生成しているので手順 3 に戻る。新規コメントを修正、返信、resolve、push し、再度手順 8 を実行する。

## 注意

- 修正を push した場合は `generated no comments` / `generated no new comments` が返るまで続ける。
- review comment 一覧、review comment への返信、review thread resolve はスキル配下 script を使う。
- Resolve 不可ならユーザーに手動依頼する。
- 「対応不要」判断が難しい場合はユーザーに確認する。
- コミットは適宜分ける。
