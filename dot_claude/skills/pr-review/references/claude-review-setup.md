# Claude レビュー CI の導入

`pr-review claude` が使う `@claude review` workflow を対象リポに入れる。リポごとに一度だけ行う。

1. `gh repo view --json nameWithOwner,visibility` で対象を確認する。
2. [../templates/claude-review.yml](../templates/claude-review.yml) を対象リポの `.github/workflows/claude-review.yml` に書き出す。既にあれば差分を確認する。
   - `author_association` ゲート（OWNER/MEMBER/COLLABORATOR）は消さない。PUBLIC リポでは token の濫用と prompt injection を防ぐ唯一の門になる。`allowed_non_write_users` も足さない。
   - secret は `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}` で参照するだけにし、値を書かない。
3. Claude GitHub App を対象リポにインストールしてもらう（`https://github.com/apps/claude`、または Claude Code の `/install-github-app`）。GitHub 上の連携でローカルには何も入らない。App が無いと投稿主体が `github-actions[bot]` になり、`wait-claude-review.py`（`claude[bot]` に厳格一致）が検知できない。
4. `gh secret list --json name --jq 'any(.[]; .name == "CLAUDE_CODE_OAUTH_TOKEN")'` が `false` なら、ユーザーに `claude setup-token` で token を作り、`gh secret set CLAUDE_CODE_OAUTH_TOKEN` で自分で登録してもらう。token を会話やリポに残さない。
5. workflow を commit skill の手順でコミットし、テスト PR で `@claude review` すると `claude[bot]` がインラインコメントと `CLAUDE_REVIEW:` サマリを返すことを伝える。

CI が `@claude review` に反応しなくなったら、まず token の失効を疑い、作り直して secret を更新する。
