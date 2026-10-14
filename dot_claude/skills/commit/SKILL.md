---
name: commit
description: コミットを行う。「コミットして」「コミット」などのリクエストで使用。
allowed-tools: Read, Grep, Glob, Bash(git config --type=bool --get agent.commitSkill), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git stash:*), Bash(pnpm:*), Bash(cargo:*)
---

# コミットスキル

## 使用可否の確認

この確認が終わるまで、下の手順には一切進まない。

`git config --type=bool --get agent.commitSkill` を単独で実行する。出力が `false` なら、このリポジトリではこのスキルの使用が禁止されている。ステージ・コミット・プッシュを一切行わず、「このリポジトリでは commit スキルが無効化されています (`agent.commitSkill=false`)」とユーザーに伝えて終了する。このコマンド自体を実行できなかった (許可が下りない等) 場合も、手順に進まずその旨を伝えて終了する。未設定なら何も出力されず終了コード 1 になるが、これは正常なので手順に進む。出力が `true` のときも手順に進む。

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
- このスキルを使わせたくないリポジトリでは `git config agent.commitSkill false` を設定する。値は `.git/config` に入るのでリポジトリには含まれず、worktree にも共有される。Claude Code では、そのリポジトリの `.claude/settings.local.json` に `"skillOverrides": {"commit": "off"}` を書くとスキル自体が読み込まれなくなる。
