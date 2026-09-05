---
name: codex-delegate
description: "Delegate a task to Codex CLI when the user requests Codex delegation, then inspect and summarize the result."
---

# Codex Delegate

Delegate the requested bounded task to `codex exec` and inspect its result. Headless process exit is the completion signal.

## Handoff

Write a task-specific temporary prompt file containing the outcome, target repository,
relevant context, deliverable, acceptance checks, and re-delegation policy. State what must be
finished before returning and which actions still need authorization. Do not paste irrelevant history
or invent restrictions on already-authorized local work.

Use the bundled wrapper from a background-capable Bash call (`run_in_background: true`):

```bash
<skill-dir>/scripts/codex-run.sh \
  --prompt-file /tmp/codex-<task>/prompt.md \
  --dir <repository> \
  --sandbox workspace-write \
  --effort medium \
  --out /tmp/codex-<task>/run.log
```

Create the task-specific temporary directory first. The wrapper closes stdin and records the full
transcript, avoiding hung stdin and buffered pipeline output. Do not assemble shell-quoted prompts by hand.

- Use `read-only` for advice/review and `workspace-write` for requested edits.
- Preserve a user-selected model with `--model`; otherwise use the configured Codex model.
- Match effort to the task (`medium` default); preserve an explicit effort choice.
- Add `--network` only when needed and `--search` for current web information.
- Add `--skip-git-check` only for an intentionally selected non-repository directory.
- Read [options.md](references/options.md) for domain restrictions or raw invocation options.
- For git-diff reviews, read [review.md](references/review.md); document/design review remains an ordinary task.

Do not use `--full-auto` or approval/sandbox bypass flags. For raw invocations, always close stdin
with `< /dev/null`; `--search` precedes `exec`. Stop only this task's process if recovery is needed.

## Completion

Wait for completion, then inspect the result and affected diff. Run checks proportionate to the
change, fix in-scope failures, and report the verified outcome and remaining blockers.
Do not repeat passing checks without new evidence or return solely because the first implementation exists.
