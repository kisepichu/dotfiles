---
name: commit
description: コミットを行う。「コミットして」「コミット」などのリクエストで使用。
allowed-tools: Read, Grep, Glob, Bash(git config --type=bool --get agent.commitSkill), Bash(git remote get-url origin), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git apply --cached:*), Bash(git commit:*), Bash(git push:*), Bash(git stash:*), Bash(pnpm:*), Bash(cargo:*)
---

# コミットスキル

## 手順

1. `git status` と `git diff` でステージ済み・未ステージの変更を確認する
2. `git log` で直近のコミットメッセージのスタイルを確認する
3. 変更内容からコミットメッセージを考える。「なぜ」を中心に、1〜2 文で簡潔にする
4. `git add <ファイル...>` でファイルをステージする。`git add -A` や `git add .` は使わず具体的なファイル名を指定する。ファイル内の一部の変更だけをステージする場合は、対象 hunk だけを含むパッチを `/tmp` に書いて `git apply --cached --recount <パッチ>` で適用する
5. commit の使用可否を確認する。各コマンドは単独で実行する
   1. `git config --type=bool --get agent.commitSkill`
      - `true`: 使用可。手順 6 へ進む。
      - `false`: 使用禁止。
      - 未設定（出力なし・終了コード 1）: 次へ。
   2. `git remote get-url origin`
      - URL の owner（ホスト直後のパス先頭。例: `git@github.com:kisepichu/x.git`、`https://github.com/kisepichu/x`）が `kisepichu` なら使用可。手順 6 へ進む。
      - それ以外、または origin が無ければ使用禁止。

   使用禁止は業務プロジェクトなど、個人リポと確認できないリポジトリであり、**エージェントがコミット・プッシュしてはいけない**。ステージした内容・コミットメッセージ案・どの条件で止まったかをユーザーに伝え、ここでスキルを終了する。確認コマンド自体を実行できなかった場合も同じ。`agent.commitSkill` の変更は提案しない。
6. `AGENTS.md` や `CLAUDE.md` にコミット前チェックの指定があれば必ず実行する。その他のチェック系コマンド（lint・test など）も実行し、失敗したら修正して再実行する
7. hook や formatter がファイルを変更した場合は、差分を確認してから該当ファイルだけ再度 `git add` する
8. `git commit --no-gpg-sign -m "<コミットメッセージ>"` でコミットする
9. 必要なら `git push` でプッシュする

## 注意事項

- コミットメッセージはプロジェクトの慣例に合わせる。
- チェックがすべて通るまでコミットしない。
- ユーザーが GPG 署名を明示した場合だけ、passphrase 入力のための `/tmp/commit_<timestamp>.sh` を生成してユーザーに実行してもらう。
