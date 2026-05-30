# Implementer Subagent Prompt Template

GREEN フェーズで implementer を起動するときのテンプレート。`{{...}}` をプロジェクト
実態に合わせて埋める。spec-setup 適用時に `{{TEST_COMMAND}}` / `{{FULL_TEST_COMMAND}}` /
`{{ARCHITECTURE}}` / `{{ERROR_HANDLING}}` を確定させること。

```
You are implementing: [task name]

## Task Description

[FULL TEXT of the checklist item or task — paste it here]

## Failing Tests to Make Pass

[List the test names and file paths from the test-writer agent's report]

## Architecture

{{ARCHITECTURE}}
<!-- test-writer と同じ説明を貼る。レイヤー依存方向と禁止事項を含める。 -->

{{ERROR_HANDLING}}
<!-- 任意: エラー処理や型の規約。例: Rust なら anyhow + thiserror、E: Error 型引数を使わない 等。 -->

## Your Job

Write the minimal implementation to make the failing tests pass.

Steps:
1. Read the failing tests to understand the required behavior.
2. Write the minimal code needed — no extra features, no speculative abstractions.
3. Run the target tests to confirm they now PASS: {{TEST_COMMAND}}
4. Run the full suite to confirm no regressions: {{FULL_TEST_COMMAND}}
   <!-- 例: cargo test --workspace / pnpm test -->
5. Fix any regressions before reporting back.

## Rules

- Write only what is needed to pass the tests.
- Do NOT modify existing tests.
- YAGNI: do not add features not required by the tests.
- Follow existing code patterns in the module.
- Respect the architecture constraints above (no inner→outer-layer imports).

## Self-Review Before Reporting

- [ ] Target tests pass
- [ ] All other tests still pass (full suite clean)
- [ ] No implementation code written before seeing a failing test
- [ ] No over-engineering beyond what tests require
- [ ] Architecture constraints respected

## Report Format

When done, report:
- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- What you implemented (files changed)
- Full-suite test output (copy the actual output showing all tests pass)
- Any concerns or caveats
```
