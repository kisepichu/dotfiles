---
name: pr-review
description: PR のレビューコメントを取得し、修正・返信・Resolve し、再レビューを依頼して完了までループする。レビュアーは Copilot（既定）か Claude（`pr-review claude`）。「PR コメント対応して」「レビュー対応」などで使用。
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git log:*), Bash(git diff:*), Bash(git rev-parse:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh --version:*), Bash(gh pr view:*), Bash(python3 ~/.claude/skills/pr-review/scripts/*), Bash(cargo:*), Bash(pnpm:*)
---

# PR レビュー対応

スクリプトは `~/.claude/skills/pr-review/scripts/`（以下 `S`）。Claude Code / Codex / omp の skill はすべてここへの symlink。引数はすべて `{owner} {repo} {num}` で始まる。PR はカレントブランチから `gh pr view --json number,url` で特定する（指定があればそれ）。

## レビュアー

| | 待ち | 前提 |
|---|---|---|
| Copilot（既定） | `S/wait-copilot-review.py` | `gh >= 2.88.0` |
| Claude（引数 `claude`） | `S/wait-claude-review.py` | 対象リポに `@claude review` CI。未導入なら [references/claude-review-setup.md](references/claude-review-setup.md) |

片方が利用量制限などで動かなければ、もう片方に切り替えてよい。

待ちスクリプトは最大 15 分ブロックし、JSON 1 行を出して終了する。exit code: **0** 指摘なし / **20** 対応すべきコメントあり / **1** タイムアウト。`--request` を付けると先に（再）レビューを依頼する。付けない初回は既存レビューを使い、無ければ依頼する。

**待ち方**: シェルのタイムアウトで切られないよう、バックグラウンド実行できる harness では背景で起動して完了通知を待つ（ポーリングや二重起動はしない）。できない harness では timeout 20 分以上で前景実行する。背景ジョブを待てない subagent 内では実行せず、親に引き継ぐ。

## ループ

1. `python3 S/wait-{copilot,claude}-review.py {owner} {repo} {num}`。0 なら終了、1 なら原因（未起動・token 失効など）を確認してユーザーに報告。
2. `python3 S/get-review-comments.py {owner} {repo} {num}` でコメント取得。`in_reply_to_id == null` がスレッド起点で、自分の返信が付いていない起点が未対応。
3. 未対応を **本質**（バグ・正しさ・セキュリティ・データ損失）か **nit**（スタイル・命名・文言・好み）に分けて対応する。
   - 妥当: 修正して commit skill の手順でコミット・push し、コミットハッシュと理由を返信する。
   - 不要: 設計意図・スコープ外などの理由を返信する。
   - 判断に迷う: ユーザーに確認する。
4. 返信は本文を `/tmp/pr-review-reply.md` に書いてから `python3 S/reply-review-comment.py {owner} {repo} {num} {comment_id} /tmp/pr-review-reply.md`。本文に command substitution は使わず、ハッシュは `git rev-parse --short HEAD` の結果を文字列で書く。
5. 返信したスレッドだけ `python3 S/resolve-review-threads.py {owner} {repo} {num} {comment_id}...` で Resolve する。失敗したらユーザーに手動 Resolve を依頼する。
6. 継続判定。次のどれかなら再レビューを依頼せず終了する。
   - このラウンドが nit 1 件だけ
   - nit のみのラウンドが 2 回続いた

   それ以外は `--request` を付けて手順 1 に戻る。
