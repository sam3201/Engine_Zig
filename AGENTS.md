# AGENTS Guidelines

This repository is a Zig-based engine. The following guidelines aid automation agents in building, linting, testing, and contributing.

- Build: `zig build -Dstatic-llvm=false` or follow `build.zig` targets. Use `run_build_and_host_server.sh` for end-to-end test harness.
- Tests: run a single test with `zig test src/** --test-filter <Name>`; for a specific file, `zig test src/path/to/file.zig --test-filter <TestName>`.
- Lint: prefer `zig build-exe` style checks; run `rg`-based searches for code smells.
- Formatting: ensure consistent formatting via `zig fmt` where applicable, and respect Zig style in code blocks.
- Error handling: prefer explicit error unions, `try` sugar, and clear error messages; surface meaningful error context.
- Imports: local modules via relative `@import` paths; avoid heavy runtime imports; keep cross-module API stable.
- Naming: PascalCase for types, lower_snake_case for functions/members; avoid underscores in types.
- Types: use `const`/`var` judiciously; prefer explicit struct tags and documented fields.
- Safety: mark unsafe blocks clearly; validate bounds and null checks.
- Cursor rules: include any project-specific cursor rules if present in `.cursor/rules/` or `.cursorrules`.
- Copilot rules: include constraints from `.github/copilot-instructions.md` if present.

## Quick Good Practices
- Keep PRs small; each commit should reflect a single intent.
- Add tests for new features; document edge cases.
- Use `# TODO` comments for gaps, with clear owner/priority.

