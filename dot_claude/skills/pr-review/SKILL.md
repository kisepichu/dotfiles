---
name: pr-review
description: PR についたレビューコメントを取得し、修正・返信・Resolve し、必要なら再レビュー依頼して完了までループする。レビュアーは Copilot（既定）か Claude（`/pr-review claude`）。「PR コメント対応して」「レビュー対応」などのリクエストで使用。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git rev-parse HEAD:*), Bash(git rev-parse --short HEAD:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh --version:*), Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr comment:*), Bash(python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/wait-claude-review.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/get-review-comments.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/reply-review-comment.py:*), Bash(python3 ~/.claude/skills/pr-review/scripts/resolve-review-threads.py:*), Bash(cargo:*), Bash(pnpm:*)
---

# PR コメント対応スキル

PR レビューコメント取得、対応、返信、Resolve まで行う。修正を push したら再レビュー依頼し、
レビュアーが「指摘なし」を返すか、**早期終了条件**（後述）を満たすまで繰り返す。

## レビュアー backend の選択

- 引数に `claude` がある（`/pr-review claude`）→ **Claude backend**: `wait-claude-review.py` を使う。
  発火は `@claude review` コメント、投稿主体は `claude[bot]`。事前に対象リポへ
  `setup-pr-review-workflow` スキルで CI を入れておくこと。
- それ以外（既定）→ **Copilot backend**: `wait-copilot-review.py` を使う。

両 backend で待ちスクリプトの exit code 契約は共通: **0 = 指摘なしで完了 / 20 = 対応すべき
コメントあり / 1 = タイムアウト**。以下の手順の `{waiter}` は選んだ backend のスクリプトに読み替える。

## 手順

### 1. PR と環境を確認

PR 番号と repo はカレントブランチから取得する。指定があればそれを使う。

```bash
gh pr view --json number,url,headRefOid,reviewRequests,latestReviews
gh --version
```

Copilot 再レビュー依頼には `gh >= 2.88.0` が必要。

### 2. レビューを待つ

レビュー取得前に必ず次を実行する。既存レビューがあればそれを使い、無ければ依頼して待つ。

**必ず `run_in_background: true` で起動する**。最大15分ポーリングして exit する。前景実行は
シェルタイムアウトで誤動作（途中で再実行・並列待ち）の原因になる。

```bash
# Copilot backend
python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py {owner} {repo} {num}
# Claude backend（/pr-review claude）
python3 ~/.claude/skills/pr-review/scripts/wait-claude-review.py {owner} {repo} {num}
```

起動したらこのターンを終え、**完了通知が来るまで待つ。ポーリングや並列の wait はしない**。
完了したら stdout（JSON 1行）と exit code を確認: **0** なら指摘なし→完了。**20** なら新規
コメントあり→手順 3。**1** ならタイムアウト→状況確認（失効/未起動などを疑う）。

### 3. コメント全件取得

```bash
python3 ~/.claude/skills/pr-review/scripts/get-review-comments.py {owner} {repo} {num}
gh pr view {num} -R {owner}/{repo} --json reviews --jq '.reviews'
```

`get-review-comments.py` は投稿者非依存で inline コメントを返す（`claude[bot]` も含む）。

### 4. 未返信コメントを特定する

`in_reply_to_id == null` がスレッド起点。起点のうち自分の返信（`in_reply_to_id == 起点 id`）が
ないものを未対応とする。

### 5. 未対応コメントを分類・対応

各コメントを **本質 / 非本質** に分類する（後述の早期終了判定にも使う）。

- **本質**: バグ・正しさ・セキュリティ・データ損失・ロジック誤りなど。
- **非本質 (nit)**: スタイル・命名・軽微な可読性・文言・主観的好みなど。

対応方針:
- 妥当: コードまたは仕様を修正し、チェック系コマンドを実行。通ったら具体的なファイルだけ
  `git add` し、`git commit --no-gpg-sign -m "..."`、必要なら `git push`。
- 今対応不要: 設計意図・スコープ外・既知制限など、理由を必ず返信する。
- 質問・確認: ユーザーに判断を仰ぐ。

### 6. 返信

返信本文を `/tmp/pr-review-reply.md` に `Write` してから送る。`$SHA=$(...)` のような代入や
command substitution は使わず、必要なら `git rev-parse HEAD` を単独実行して結果を文字列で書く。

```bash
python3 ~/.claude/skills/pr-review/scripts/reply-review-comment.py {owner} {repo} {num} {comment_id} /tmp/pr-review-reply.md
```

### 7. 返信済みスレッドのみ Resolve

全未解決を一括 Resolve せず、返信済みスレッドだけ Resolve する。

```bash
python3 ~/.claude/skills/pr-review/scripts/resolve-review-threads.py {owner} {repo} {num} {comment_id}...
```

### 8. 継続判定（早期終了ロジック）

このラウンドの新規コメントの分類（手順 5）をもとに、再レビューするか終了するかを決める:

1. **指摘なし**（waiter が exit 0）→ 終了。
2. このラウンドが **非本質のみ かつ 1 件だけ** → 終了（その 1 件は対応 or 見送り理由を返信して締める）。
3. このラウンドが **非本質のみ で、直前ラウンドも非本質のみ**（= 非本質のみ 2 連続）→ 終了。
4. それ以外（**本質が 1 件でもある**、または非本質のみだが初回・複数件）→ 修正/返信/Resolve して
   **手順 9 へ（再レビュー継続）**。

終了する場合は、残った nit を対応 or「軽微につき今回は見送り」を返信して Resolve し、
**再レビュー要求はしない**。`generated no comments` を待たずこの規則で切り上げてよい。

### 9. push 後に再レビュー依頼して待つ

修正を commit / push したら、再レビューを依頼して待つ。手順 2 と同様 **必ず
`run_in_background: true` で起動し、完了通知まで待つ。ポーリング・並列待ちはしない**。

```bash
# Copilot backend
python3 ~/.claude/skills/pr-review/scripts/wait-copilot-review.py {owner} {repo} {num} --request
# Claude backend
python3 ~/.claude/skills/pr-review/scripts/wait-claude-review.py {owner} {repo} {num} --request
```

完了したら exit code を確認: **0** なら完了。**20** なら手順 3 に戻り、新規コメントを分類して
手順 8 の継続判定にかける。**1** ならタイムアウト。

## 注意

- 待ちスクリプトは必ず `run_in_background: true` で起動。完了通知まで待ち、ポーリングや並列の
  wait 再起動はしない。レビューは数分〜十数分かかることがあり、前景実行はシェルタイムアウトで
  誤動作の原因になる。
- 早期終了ロジック（手順 8）で、非本質 nit が続く場合は早めに切り上げる。本質的な指摘がある間は
  続ける。
- review comment 一覧・返信・thread resolve はスキル配下 script を使う（投稿者非依存で
  Copilot/Claude どちらの inline コメントにも効く）。
- Resolve 不可ならユーザーに手動依頼する。「対応不要」判断が難しい場合はユーザーに確認する。
- コミットは適宜分ける。
- Claude backend で waiter が exit 1（タイムアウト）を繰り返すときは、リポに
  `setup-pr-review-workflow` の CI が入っているか、Claude GitHub App が認可済みか、
  `CLAUDE_CODE_OAUTH_TOKEN` が有効（未失効）かを確認する。
- `wait-claude-review.py` は投稿主体を `claude[bot]`（Bot タイプ）に**厳格一致**で照合する
  （なりすまし `claude-*` による偽マーカーでループを誤終了させないため）。実際の login が
  異なる場合のみ `--bot-login <login>` で指定する。`--request` 無しの初回確認では、現在の
  head コミットより古いレビューは stale として無視し新規レビューを依頼する。
