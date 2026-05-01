---
name: pr-review
description: PR についたレビューコメントを取得し、修正・返信・Resolve するまでを行う。「PR コメント対応して」「レビュー対応」などのリクエストで使用。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh api:*), Bash(gh pr:*), Bash(cargo:*), Bash(pnpm:*)
---

# PR コメント対応スキル

PR レビューコメント取得、対応、返信、Resolve まで行う。

## 手順

### 1. コメント全件取得

```bash
gh api repos/{owner}/{repo}/pulls/{num}/comments --jq '[.[] | {id, in_reply_to_id, created_at, path, line, body}]'
gh api repos/{owner}/{repo}/pulls/{num}/reviews
```

### 2. 未返信コメントを特定する

`in_reply_to_id` が null のコメントがスレッドの起点。
起点コメントのうち、自分の返信 (`in_reply_to_id == そのコメントの id`) が存在しないものを未対応とする。

### 3. 未対応コメントを分類・対応

- 妥当: コードまたは仕様を修正し、チェック系コマンドを実行する。通ったら具体的なファイルだけ `git add` し、`git commit --no-gpg-sign -m "..."`、必要なら `git push` する。
- 今対応不要: 設計意図、スコープ外、既知制限など、今対応するべきでない理由を必ず返信する。
- 質問・確認: ユーザーに判断を仰ぐ。

### 4. 返信

`-X POST` 必須。省略すると GET になり 404 になる。

```bash
gh api -X POST repos/{owner}/{repo}/pulls/{num}/comments/{comment_id}/replies \
  -f body="Fixed in <commit_sha>." --jq '.id'

gh api -X POST repos/{owner}/{repo}/pulls/{num}/comments/{comment_id}/replies \
  -f body="<対応不要の理由>" --jq '.id'
```

### 5. 返信済みスレッドのみ Resolve

全未解決を一括 Resolve しない。push 後に新しいコメントが追加されることがあるため、返信していないスレッドを巻き込む危険がある。

```bash
gh api graphql -f query='
{
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {num}) {
      reviewThreads(first: 50) {
        nodes { id isResolved comments(first:1){ nodes{ databaseId } } }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | {threadId: .id, commentId: .comments.nodes[0].databaseId}'

gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "{thread_id}"}) { thread { isResolved } } }'
```

### 6. 未返信コメントの再確認

```bash
gh api "repos/{owner}/{repo}/pulls/{num}/comments?per_page=100" --jq '[.[] | {id, in_reply_to_id}]' | python3 -c "
import json, sys
data = json.load(sys.stdin)
roots = {c['id'] for c in data if c['in_reply_to_id'] is None}
replied = {c['in_reply_to_id'] for c in data if c['in_reply_to_id'] is not None}
unanswered = roots - replied
print('未返信:', len(unanswered), sorted(unanswered))
"
```

未返信 0 件を確認したら完了。

## 注意

- Resolve 後に必ず再取得して未返信 0 件を確認する。
- Resolve 不可ならユーザーに手動依頼する。
- 「対応不要」判断が難しい場合はユーザーに確認する。
- 複数コメントはまとめて 1 コミットでよい。
