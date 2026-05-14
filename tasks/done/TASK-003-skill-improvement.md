# TASK-003: skill-improvement

## 参照仕様

- User request on 2026-05-14: remove fatal skill mistakes first, then create and run a Codex-side skill improvement skill.
- AGENTS.md

## チェックリスト

- [x] `.claude/skills` source tree の `codex` 文字列混入を調査する。
- [x] `spec-workflow` を本来の spec command setup 用 skill として復元し、分かりやすい名前へ変更する。
- [x] `.claude/skills` source tree から不要な `codex` 文字列をなくす。
- [x] Codex 側に `skill-improvement` skill を作成する。
- [x] `skill-improvement` skill を一回実行して、実運用上の改善点を反映する。
- [x] 検証を実行し、結果を記録する。

## 完了条件

- [x] `dot_claude/skills` 内に不要な `codex` 文字列が残っていない。
- [x] spec command setup 用 skill が `spec-setup` として管理されている。
- [x] `dot_codex/skills/skill-improvement` が Codex 専用 skill として存在する。
- [x] skill validation と public-safety/pre-commit 相当の検証が通っている。

## 作業ログ

- 2026-05-14: 作業開始。repo 内の `spec-workflow` と `cross-review`、ホーム側の `spec-*-template.md` を確認。
- 2026-05-14: `spec-workflow` を削除し、`spec-setup` と templates を追加。`cross-review` は `.claude/skills` 内の Codex 依存を消すため削除。Codex 専用 `skill-improvement` を追加。
- 2026-05-14: `skill-improvement` を `spec-setup` に一回適用。適用条件と検証手順を追加し、検証スクリプトを新しい skill 配置へ追従。
- 2026-05-14: `rg`, `scripts/validate-skills.sh`, `scripts/check-chezmoi-managed.sh`, `prek run --all-files` が通過。
