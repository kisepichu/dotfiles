# TASK-014: Claude を GitHub Actions で PR レビューさせ、/pr-review から選べるようにする

## 参照仕様

- User request on 2026-06-02（PR #16 マージ後）: Copilot の PR レビューがレート制限で停止した。ループ継続の条件を緩め、また Copilot 以外にも **Claude が Actions で PR レビュー**できるようにする。リポジトリ secret に `CLAUDE_CODE_OAUTH_TOKEN`、`@claude review` コメントで発火。`/pr-review` を微調整し、Copilot へのレビューリクエストの代わりに **Claude へリクエストコメント**する（`/pr-review claude` のように引数で指定）。
- 追加合意:
  - 認証は **OAuth のみ**（`CLAUDE_CODE_OAUTH_TOKEN` を使う。従量課金 API は使わない）。モデルは **Sonnet など軽量**（`--model claude-sonnet-4-6`）で枠消費を抑える。
  - workflow YAML は dotfiles が直接管理するものではないので、**`setup-pr-review-workflow` 新スキル**で任意プロジェクトに workflow 雛形＋セットアップ手順を展開する。
  - **早期切り上げ**: `no comments` でなくてもレビュー内容を見て続行可否を判定（後述）。Copilot 経路にも適用。
- 既存資産: `dot_claude/skills/pr-review/`（SKILL.md＋`wait-copilot-review.py` / `get-review-comments.py` / `reply-review-comment.py` / `resolve-review-threads.py` / `validate-gh-api.py`）。

## 背景

- Copilot はサードパーティ枠でレート制限に当たり無応答化（PR #16 で5回後に停止）。自前制御できる Claude へ。
- 現行ループは Copilot 固有（発火 `--add-reviewer @copilot`、終了は `copilot-pull-request-reviewer` の `generated no comments`）。Claude は発火経路・投稿主体・終了マーカーが違うので作り直す。
- 終了条件が `no comments` のみだと nit が続いたとき枠を浪費 → 早期切り上げを入れる。

## 前提（`claude-code-action@v1`, 2026-06-02 調査）

- `anthropics/claude-code-action@v1`。`prompt` ＋ `claude_args`（`--model claude-sonnet-4-6 --max-turns N` 等）。
- 認証: `claude setup-token` → secret `CLAUDE_CODE_OAUTH_TOKEN` → `claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`。サブスク枠消費で per-token 従量課金ではない。
- 発火: `@claude` は `on: issue_comment`/`pull_request_review_comment` で起動（App 不要）。ローカルからは `gh pr comment {num} --body "@claude review"`。
- GitHub 上の Web 連携使用（`github.com` で認可、`/install-github-app` でも可。ローカルには何も入れない）。App を入れると投稿主体が **`claude[bot]`** になり検知が綺麗・公式サポート。App 無し（`GITHUB_TOKEN`）だと `github-actions[bot]` 主体・非サポート → App を入れて `claude[bot]` 採用。
- permissions: `contents: read` / `pull-requests: write` / `issues: write`。`concurrency` でキャンセル推奨。
- docs: `code.claude.com/docs/en/github-actions`、`github.com/anthropics/claude-code-action`。

## 方針（確定）

- 認証 = OAuth（`CLAUDE_CODE_OAUTH_TOKEN`）。軽量モデル（Sonnet）。
- 発火 = オンデマンドのみ（`@claude review`）。`pull_request` 自動レビューは入れない。
- 出力 = インラインレビュー（解決可能スレッド、主体 `claude[bot]`）。既存 get/reply/resolve を流用。
- 公開リポゲート（必須）: 本文に `@claude review` ＋ `author_association ∈ {OWNER, MEMBER, COLLABORATOR}`。`allowed_non_write_users` は使わない。
- workflow はスキル展開。Copilot はフォールバックに残す（`/pr-review` 既定 copilot / `/pr-review claude`）。

## 早期終了ロジック（/pr-review 共通・agent 判定。両 backend に適用）

レビュー往復ごとに新規コメントを本質（バグ/正しさ/セキュリティ/データ損失）／非本質 nit（スタイル/命名/軽微/文言/好み）に分類:

1. **no comments** → 無条件終了。
2. 非本質のみ かつ 1 件だけ → 終了。
3. 非本質のみ が 2 連続 → 終了。
4. 本質が 1 件でもあれば対応して継続（非本質のみだが初回・複数件は対応して継続）。

締める際は残り nit を対応 or「軽微につき見送り」を返信し Resolve、再レビュー要求はしない。Copilot 経路でも `generated no comments` を待たずこの規則で切り上げる。

## 設計メモ

### A. 新スキル `setup-pr-review-workflow`（`dot_claude/skills/`、chezmoi 管理）

実行したプロジェクトに Claude レビュー CI を一式セットアップ:

1. `.github/workflows/claude-review.yml` をそのプロジェクトに合わせて生成（そのリポジトリ直下・chezmoi 管理外）。
2. Claude GitHub App の認可手順を案内（github.com / `/install-github-app`）。
3. `CLAUDE_CODE_OAUTH_TOKEN` secret 登録手順。
4. 公開/非公開リポのゲート差分を説明。

workflow 雛形の要点:

- `on: issue_comment(created)` ＋ `pull_request_review_comment(created)`。`pull_request` は入れない。
- `if`: 本文 `@claude review` ＋ `author_association ∈ {OWNER,MEMBER,COLLABORATOR}`。
- `permissions`: contents:read / pull-requests:write / issues:write。`concurrency: cancel-in-progress`。
- `claude-code-action@v1` with `claude_code_oauth_token`。`claude_args: --model claude-sonnet-4-6 --max-turns N`。`--allowedTools` は付けない（v1 は GitHub コメント/レビュー系を既定許可。指定すると既定を置換して投稿が壊れる）。
- `prompt`: 観点（バグ/セキュリティ/簡潔化）、インライン投稿、指摘ゼロなら明示マーカー（例 `CLAUDE_REVIEW: no issues found`）を必ず出す。`/code-review` 基準の流用検討。
- secretlint / public-safety を通す（literal secret を置かない）。

### B. `/pr-review` skill 改修

- 引数で backend 選択（既定 copilot / `claude`）。SKILL.md に分岐、`allowed-tools` に新スクリプト追加。
- 新スクリプト `wait-claude-review.py`（Copilot 版の Claude 版）:
  - 発火(`--request`): `@claude review` コメントを投稿（実装は `gh api -X POST repos/.../issues/{num}/comments`。サーバ側 timestamp を baseline に使うため。`gh pr comment` でも等価）。
  - 検知: トリガ timestamp 以降に `claude[bot]` が出した inline review / 進捗コメント完了・ゼロ指摘マーカーで判定。
  - exit code は Copilot 版と統一（ゼロ→0、新規あり→20、timeout→1）。`run_in_background` 起動・15分上限。
- 早期終了ロジックを SKILL.md ループ手順に追加（両 backend 共通）。
- get/reply/resolve は inline レビューなら流用可。`claude[bot]` フィルタ追加要否を実装時確認。
- README/SKILL.md に backend 切替・Claude 版発火/終了マーカー・トークン再生成・早期終了規則を記載。

## 実装時に確認

- 指摘ゼロマーカーの文言と inline 投稿の確実性（prompt で強制できるか）。
- `claude[bot]` の正確な `login` 実値（検知フィルタ用）をテスト PR で確認。

## チェックリスト

- [x] `task-014-...` ブランチを切る（独立 PR）。
- [x] スキル `setup-pr-review-workflow` 作成（workflow 雛形＋App/secret 手順、公開リポゲート、OAuth、Sonnet、concurrency、max-turns）。
- [x] `wait-claude-review.py` 実装（`@claude review` 発火、`claude[bot]` 検知、ゼロ指摘マーカー、exit 0/20/1）。
- [x] `/pr-review` を backend 引数対応に改修（SKILL.md 分岐・allowed-tools）。Copilot 経路維持。
- [x] 早期終了ロジックを SKILL.md に追加（両 backend）。
- [x] get/reply/resolve の `claude[bot]` 対応を確認（投稿者非依存で流用可・無修正）。
- [x] SKILL.md（pr-review / setup-pr-review-workflow）にセットアップ・運用・早期終了規則を記載。
- [x] dotfiles 自身にも `.github/workflows/claude-review.yml` を設置（main 到達後に有効）。
- [x] secretlint / `check-public-safety.sh` / `check-chezmoi-managed.sh` / `prek run --all-files` を通す。
- [ ] テスト PR で end-to-end（`@claude review` → inline → `/pr-review claude` ループ → 早期終了/ゼロ指摘で終了）。**workflow が main に到達し、Claude GitHub App 認可後に実施**（issue_comment はデフォルトブランチ main の workflow で発火するため）。

## 完了条件

- [ ] `setup-pr-review-workflow` で対象リポに Claude レビュー CI を一式セットアップできる。
- [ ] テスト PR で `@claude review` により Claude が起動し `claude[bot]` でインラインレビューを投稿。
- [ ] `/pr-review claude` のループが回り、ゼロ指摘または早期終了規則で終了する。
- [ ] 公開リポで非権限ユーザーのコメントでは起動しない（author_association ゲート）。
- [ ] `/pr-review`（引数なし）の Copilot 経路が後方互換で動き、早期終了規則も効く。
- [ ] 各種チェック（secretlint/public-safety/chezmoi/prek）が通る。

## 作業ログ

- 2026-06-02: PR #16 マージ後に起票。`claude-code-action@v1`（`prompt`+`claude_args`、OAuth、`@claude` 発火、公開リポゲート、inline、App は GitHub 上の Web 連携で `claude[bot]` 主体）を調査。OAuth 専用・Sonnet・workflow のスキル化（`setup-pr-review-workflow`）・早期終了ロジック（両 backend）を確定。
- 2026-06-02: 実装。新スキル `setup-pr-review-workflow`（SKILL.md＋`templates/claude-review.yml`）、`wait-claude-review.py`（`@claude review` 発火・`claude[bot]`＋`CLAUDE_REVIEW:` マーカー検知・exit 0/20/1、sticky 編集に備え effective ts=max(created,updated)）、`/pr-review` SKILL.md を backend 引数＋早期終了ロジック対応に改修。get/reply/resolve は投稿者非依存で無修正流用。dotfiles 自身にも `.github/workflows/claude-review.yml` を設置。`wait-claude-review.py` の純ロジックを ephemeral 単体テスト（13 件）で検証、prek 全通過。E2E は workflow が main 到達＋App 認可後（issue_comment はデフォルトブランチ発火のため本 PR 内では不可）。
