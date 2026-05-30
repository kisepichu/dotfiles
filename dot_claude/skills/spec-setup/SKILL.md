---
name: spec-setup
description: プロジェクトに spec-do/spec-review/spec-update コマンドをセットアップする。「spec コマンドを入れて」「仕様駆動コマンドをセットアップ」などの依頼で使用。
metadata:
  short-description: spec コマンドセットアップ
---

# Spec Setup

新しいプロジェクト、または既存プロジェクトに仕様駆動作業用の slash command を設置する。

## 適用条件

- ユーザーが project-local な `spec-do`, `spec-review`, `spec-update` command の導入を求めている。
- 既存 command の改善依頼なら、この skill のテンプレートを基準に差分だけ反映する。
- 仕様作業そのものを進める依頼なら、この skill ではなくプロジェクト内の command やタスク手順を使う。

## 手順

1. 対象プロジェクトのルールを確認する。
   - `AGENTS.md`, `CLAUDE.md`, `README.md`, 既存の `.claude/commands/` を読む。
2. `.claude/commands/` がなければ作成する。
3. この skill の `templates/` から以下をコピーする。
   - `spec-do.md` -> `.claude/commands/spec-do.md`
   - `spec-review.md` -> `.claude/commands/spec-review.md`
   - `spec-update.md` -> `.claude/commands/spec-update.md`
   - テストのある開発プロジェクトなら TDD subagent テンプレも:
     - `templates/agents/test-writer.md` -> `.claude/agents/test-writer.md`
     - `templates/agents/implementer.md` -> `.claude/agents/implementer.md`
4. プロジェクトの実態に合わせてテンプレートを調整する。
   - 仕様ファイルの探索順
   - タスクディレクトリと命名規則
   - ブランチ作成ルール
   - 検証コマンド
   - 公開安全性や secret 管理の注意点
   - TDD を使う場合、agent テンプレと spec-do.md の `{{...}}` プレースホルダを埋める:
     - `{{TEST_COMMAND}}` / `{{FULL_TEST_COMMAND}}` — 単体/全体のテスト実行コマンド
     - `{{TEST_LOCATION}}` — テストの置き場所 (層・ディレクトリ規則)
     - `{{ARCHITECTURE}}` — レイヤー構成と依存方向の禁止事項
     - `{{ERROR_HANDLING}}` — エラー処理や型の規約 (任意)
     - `{{TEST_NAME_LANG}}` — テスト名の言語と例
     - `{{VERIFY_COMMANDS}}` — 仕上げの検証コマンド一式
5. subagent の起動方法を確認する (spec-do.md の「offload 主軸」節)。
   - コスト節約で別アカウントへ逃がす場合は、利用者が `$CLAUDE_OFFLOAD_CONFIG_DIR`
     (offload 先の config ディレクトリ) を環境変数で用意する前提。値は command に書かない。
   - offload を使わないなら Agent (Task) ツールのフォールバックで動く。
6. 既存コマンドがある場合は上書きせず、差分を確認して必要な変更だけ反映する。
7. 最後に追加・変更したファイルと、プロジェクト固有に調整した点を報告する。

## 検証

- `.claude/commands/spec-do.md`, `spec-review.md`, `spec-update.md` が存在する。
- 3 command すべてが対象プロジェクトの仕様配置、タスク配置、検証コマンドに合っている。
- TDD を使う場合、`.claude/agents/test-writer.md` と `implementer.md` が存在し、
  `{{...}}` プレースホルダがプロジェクト実態の値で埋まっている。
- 既存 command を更新した場合は、上書きではなく意図した差分だけになっている。

## テンプレート

- [templates/spec-do.md](templates/spec-do.md)
- [templates/spec-review.md](templates/spec-review.md)
- [templates/spec-update.md](templates/spec-update.md)
- [templates/agents/test-writer.md](templates/agents/test-writer.md)
- [templates/agents/implementer.md](templates/agents/implementer.md)

## 注意

- テンプレートは出発点であり、プロジェクトごとのルールを優先する。
- secret, private URL, host-specific path, machine-local identity values をテンプレートや command に入れない。
- command と skill の役割を混ぜない。ここで作るのは project-local な slash command。
