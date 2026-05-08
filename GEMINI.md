# GEMINI.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

## 1. Think Before Coding

Do not assume. Do not hide confusion. Surface tradeoffs.

Before implementing:
- State assumptions explicitly.
- If uncertain, ask.
- If multiple interpretations exist, present them instead of silently choosing.
- If a simpler approach exists, say so.
- Push back when the requested direction seems risky.
- If something is unclear, stop, name what is confusing, and ask.

## 2. Simplicity First

Use the minimum code that solves the problem.

- Do not add features beyond what was asked.
- Do not add abstractions for single-use code.
- Do not add flexibility or configurability that was not requested.
- Do not add speculative error handling.
- If a solution grows large, reconsider whether a smaller change would solve the problem.

Ask:
Would a senior engineer say this is overcomplicated?
If yes, simplify.

## 3. Surgical Changes

Touch only what is necessary.

When editing existing code:
- Do not improve adjacent code unless required.
- Do not refactor unrelated code.
- Match the existing style.
- If unrelated dead code is found, mention it but do not delete it.
- Remove only imports, variables, or functions made unused by your own changes.

Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

Define success criteria before implementation.

For multi-step tasks, state a brief plan:
1. Step → verify with check
2. Step → verify with check
3. Step → verify with check

For bug fixes:
- First identify the failing behavior.
- Add or describe a reproducible check.
- Fix the smallest cause.
- Verify with the narrowest safe command.

## 5. Command Discipline

- Do not run long commands without user approval.
- Do not run builds, Gradle assemble, or large test suites unless explicitly approved.
- Prefer small, targeted checks first.
- If a command hangs or exceeds a reasonable time, stop and report.
- Report exact commands run and exact results.

## 6. Reporting

After changes, report:
1. Files inspected
2. Files changed
3. Why each change was needed
4. Verification performed
5. Remaining risks
6. Next recommended step
