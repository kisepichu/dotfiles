---
name: commit
description: コミットを行う。「コミットして」「コミット」などのリクエストで使用。
allowed-tools: Read, Grep, Glob, Bash(git config --type=bool --get agent.commitSkill), Bash(git remote get-url origin), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git stash:*), Bash(pnpm:*), Bash(cargo:*)
---

# コミットスキル

## 使用可否の確認

この確認が終わるまで、下の手順には一切進まない。各コマンドは単独で実行する。

1. `git config --type=bool --get agent.commitSkill`
   - `true`: 使用可。手順へ進む。
   - `false`: 使用禁止。
   - 未設定（出力なし・終了コード 1）: 2 へ。
2. `git remote get-url origin`
   - URL の owner（ホスト直後のパス先頭。例: `git@github.com:kisepichu/x.git`、`https://github.com/kisepichu/x`）が `kisepichu` なら使用可。手順へ進む。
   - それ以外、または origin が無ければ使用禁止。

使用禁止なら、ステージ・コミット・プッシュを一切行わず、どの条件で止まったかをユーザーに伝えて終了する。確認コマンド自体を実行できなかった場合も同じ。個人リポ以外で使いたい場合や origin の無いリポでは、ユーザーが `git config agent.commitSkill true` を設定する（`.git/config` に入るのでリポジトリには含まれない）。

## 手順

1. `git status` と `git diff` でステージ済み・未ステージの変更を確認する
2. `git log` で直近のコミットメッセージのスタイルを確認する
3. 変更内容からコミットメッセージを考える。「なぜ」を中心に、1〜2 文で簡潔にする
4. `git add <ファイル...>` でファイルをステージする。`git add -A` や `git add .` は使わず具体的なファイル名を指定する
5. `AGENTS.md` や `CLAUDE.md` にコミット前チェックの指定があれば必ず実行する。その他のチェック系コマンド（lint・test など）も実行し、失敗したら修正して再実行する
6. hook や formatter がファイルを変更した場合は、差分を確認してから該当ファイルだけ再度 `git add` する
7. `git commit --no-gpg-sign -m "<コミットメッセージ>"` でコミットする
8. 必要なら `git push` でプッシュする

## 注意事項

- コミットメッセージはプロジェクトの慣例に合わせる。
- チェックがすべて通るまでコミットしない。
- ユーザーが GPG 署名を明示した場合だけ、passphrase 入力のための `/tmp/commit_<timestamp>.sh` を生成してユーザーに実行してもらう。
