### 3a. Review tasks

When the task is a code review of changes in a git repository, use the dedicated `review` subcommand instead of a hand-written review prompt:

```
codex exec review <target> [-o <output-file>] < /dev/null
```

Pick the review target:

| Flag | Reviews |
|------|---------|
| `--uncommitted` | Staged, unstaged, and untracked changes |
| `--base <branch>` | Changes against a base branch (PR-style review) |
| `--commit <SHA>` | Changes introduced by a specific commit |

**Custom review instructions cannot be combined with a target flag.** As of codex 2026-07, passing a prompt argument together with `--uncommitted` (and likewise the other target flags) errors with `the argument '--uncommitted' cannot be used with '[PROMPT]'`. A bare `codex exec review "<instructions>"` (no target flag) accepts the prompt and reviews uncommitted changes. So: default to the target flag without instructions; when a review focus is essential, drop the target flag (uncommitted scope) or fall back to a regular `codex exec -s read-only` prompt for other scopes.

Notes:

- `review` runs in a read-only sandbox automatically — there is no `-s` flag, and the §1/§2a sandbox/effort defaults do not apply. Only pass `-m` or `-c` flags when the user explicitly asks for them.
- Unless the user specified an output location, pass `-o /tmp/codex-reviews/<descriptive-name>-<YYYYMMDD-HHmmss>.md` (create the directory first with `mkdir -p /tmp/codex-reviews`) so the final review is written to a file. After completion, read the file and summarize it to the user with the file path.
- Review-focus requests (e.g. "セキュリティ観点で"): see the constraint above — prompt and target flag are mutually exclusive. Use `codex exec review "<focus>"` for uncommitted-scope focused reviews; otherwise omit the focus.
- Findings come back with priority labels ([P1], [P2], …) and `file:line` locations — preserve these in the summary.
- The stdin rule (§3) and `run_in_background: true` apply here as usual.
- For review requests that are NOT about a git diff (e.g. "review this file/design doc"), the `review` subcommand does not apply — fall back to a regular `codex exec -s read-only` prompt.
