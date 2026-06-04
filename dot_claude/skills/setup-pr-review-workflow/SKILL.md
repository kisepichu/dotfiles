---
name: setup-pr-review-workflow
description: 任意のプロジェクトに「@claude review で Claude が PR をレビューする」GitHub Actions を一式セットアップする。workflow 雛形の生成・Claude GitHub App 認可・CLAUDE_CODE_OAUTH_TOKEN secret 登録を案内する。「Claude レビュー CI を入れて」「PR レビュー workflow をセットアップ」などで使用。
allowed-tools: Read, Write, Edit, Bash(gh repo view:*), Bash(gh secret list:*), Bash(mkdir:*), Bash(git add:*), Bash(git status:*), Bash(git rev-parse:*)
---

# Claude PR レビュー CI セットアップスキル

実行したプロジェクトに、`@claude review` コメントで Claude が PR をインラインレビューする
GitHub Actions を導入する。`/pr-review claude` と対で使う（あちらがトリガコメントを投げ、
`claude[bot]` のレビューを待って取り込む）。

## 前提知識

- アクションは `anthropics/claude-code-action@v1`。認証は OAuth（`CLAUDE_CODE_OAUTH_TOKEN`）。
  サブスク枠を消費する（per-token 従量課金ではない）。軽量モデル（Sonnet）で枠を節約する。
- **Claude GitHub App はローカルのデスクトップアプリではない**。GitHub 上の Web 連携で、
  `github.com` の App ページ、または Claude Code の `/install-github-app` で認可する。
  入れると投稿主体が `claude[bot]` になり、`/pr-review claude` の検知が綺麗になる。
- 発火（`on: issue_comment` など）は App 無しでも起きるが、その場合の投稿主体は
  `github-actions[bot]` で非サポート。**App を入れて `claude[bot]` 主体にする**。

## 手順

### 1. 対象リポジトリを確認

```bash
gh repo view --json nameWithOwner,visibility --jq '{repo: .nameWithOwner, visibility: .visibility}'
```

`visibility` を覚えておく。PUBLIC なら濫用対策の author_association ゲートが必須（雛形は既定で入っている）。

### 2. workflow を生成

雛形をプロジェクト直下の `.github/workflows/claude-review.yml` に書き出す。雛形は
`~/.claude/skills/setup-pr-review-workflow/templates/claude-review.yml` にある。Read して
内容を確認し、対象リポに合わせて（必要なら `--max-turns` やレビュー観点を調整して）`Write` する。

- `.github/workflows/` はそのリポジトリ自身の CI メタで、chezmoi 管理ではない。
- PUBLIC リポでは `if` の author_association ゲート（OWNER/MEMBER/COLLABORATOR）を必ず残す。
  `allowed_non_write_users` は追加しない。
- secret は `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` 参照のみ。literal なトークンを書かない。

### 3. Claude GitHub App を認可（一度きり・GitHub 上）

ユーザーに次を案内する（ローカルには何も入らない）:

- Claude Code から `/install-github-app` を実行（ブラウザで GitHub の認可ページが開く）、または
- `https://github.com/apps/claude` を開いて対象リポにインストール。

`claude[bot]` がそのリポに対してコメント／レビューを投稿できるようになる。

### 4. CLAUDE_CODE_OAUTH_TOKEN secret を登録

既に登録済みかを確認（パイプ・`grep` を使わない単独コマンド。true なら登録済み）:

```bash
gh secret list --json name --jq 'any(.[]; .name == "CLAUDE_CODE_OAUTH_TOKEN")'
```

未登録なら、ユーザーに次を案内する（トークン値は会話やリポに残さない）:

- `claude setup-token` でトークンを生成（使いたいサブスクのアカウントで）。
- リポの Settings → Secrets and variables → Actions に `CLAUDE_CODE_OAUTH_TOKEN` として登録、
  または `! gh secret set CLAUDE_CODE_OAUTH_TOKEN`（`!` 接頭辞でユーザー自身が対話入力）。

> トークンは期限切れがある。CI が `@claude` に無反応になったら失効を疑い、再生成して secret を更新する。

### 5. コミットして案内

`.github/workflows/claude-review.yml` を `git add` する。コミットは commit スキル／ユーザー判断に委ねる。
最後に動作確認手順を伝える:

1. 対象リポでテスト PR を作る。
2. その PR に `@claude review` とコメント（または `/pr-review claude`）。
3. workflow が起動し、`claude[bot]` がインラインレビュー＋ `CLAUDE_REVIEW:` サマリを投稿する。

## 注意

- これはレビュー専用の workflow。`@claude` を含むコメントで起動するので、汎用の `@claude` 用途を
  別途使いたい場合は別 workflow を用意する。
- PUBLIC リポでゲートを緩めない（トークン濫用・prompt injection 防止）。
- 既に `.github/workflows/claude-review.yml` がある場合は上書き前に差分を確認する。
