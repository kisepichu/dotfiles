---
name: commit
description: コミットを行う。「コミットして」「コミット」などのリクエストで使用。
allowed-tools: Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git stash:*), Bash(pnpm:*), Bash(cargo:*)
---

# コミットスキル

## 手順

1. `git status` と `git diff` でステージ済み・未ステージの変更を確認する
2. `git log` で直近のコミットメッセージのスタイルを確認する
3. 変更内容からコミットメッセージを考える。「なぜ」を中心に、1〜2 文で簡潔にする
4. `git add <ファイル...>` でファイルをステージする。`git add -A` や `git add .` は使わず具体的なファイル名を指定する
5. `AGENTS.md` や `CLAUDE.md` にコミット前チェックの指定があれば必ず実行する。この repository では `prek run --all-files`、なければ `pre-commit run --all-files` を実行して通す
6. その他のチェック系コマンドをすべて実行して通るか確認する。失敗があれば修正して再実行する
7. hook や formatter がファイルを変更した場合は、差分を確認してから該当ファイルだけ再度 `git add` する
8. `git commit --no-gpg-sign -m "<コミットメッセージ>"` でコミットする
9. 必要なら `git push` でプッシュする

## 注意事項

- コミットメッセージはプロジェクトの慣例に合わせる。
- チェックがすべて通るまでコミットしない。
- ユーザーが GPG 署名を明示した場合だけ、passphrase 入力のための `/tmp/commit_<timestamp>.sh` を生成してユーザーに実行してもらう。
