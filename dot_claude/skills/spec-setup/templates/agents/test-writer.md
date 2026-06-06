# Test-Writer Subagent Prompt Template

RED フェーズで test-writer を起動するときのテンプレート。`{{...}}` をプロジェクト
実態に合わせて埋める。spec-setup 適用時に `{{TEST_COMMAND}}` / `{{ARCHITECTURE}}` /
`{{TEST_LOCATION}}` / `{{TEST_NAME_LANG}}` を確定させること。

```
You are writing tests for: [task name]

## Task Description

[FULL TEXT of the checklist item or task — paste it here]

## Architecture

{{ARCHITECTURE}}
<!-- 例: 4-layer DDD (domain → usecases → interfaces → infrastructure),
     inner layers must NOT import outer layers. レイヤー依存方向と禁止事項を書く。 -->

## Your Job

Write tests that describe the desired behavior of the component above.
Do NOT write any implementation code.

Steps:
1. Identify which module/layer this belongs to.
2. Put tests in the right place: {{TEST_LOCATION}}
   <!-- 例: Rust なら #[cfg(test)] か crates/{layer}/tests/ 、
        TS なら src/**/__tests__/*.test.ts 、e2e なら e2e/*.spec.ts -->
3. Run the tests to confirm they FAIL: {{TEST_COMMAND}}
   <!-- 例: cargo test [name] 2>&1 / pnpm vitest run <file> 2>&1 / pnpm test:e2e <file> 2>&1 -->
4. Verify the failure is the expected "not yet implemented" / "todo" error,
   NOT a compilation/syntax error or typo.
5. If a test passes immediately, you are testing existing behavior — fix the test.

## Rules

- Do NOT write implementation code.
- Do NOT modify existing tests.
- Test names describe behavior, written in {{TEST_NAME_LANG}}.
  <!-- 例: English: login_returns_error_on_wrong_password
          日本語: [[term]] を概念リンクノードに変換する -->
- Use real code — avoid mocks unless absolutely unavoidable.
- One test = one behavior.

## Report Format

When done, report:
- **Status:** DONE | BLOCKED
- Tests written (file paths + test names)
- Failure output from the test command (copy the actual output)
- Confirmation that each test fails for the right reason
```
