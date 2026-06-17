---
name: codex-delegate
description: Delegate tasks to OpenAI Codex CLI (codex exec). Use when the user asks to delegate work to Codex, or mentions "codex" in the context of task delegation (e.g. "codexに任せて", "codexでやって", "codexに委任", "delegate to codex", "let codex handle it", "use codex for this").
---

# Codex Delegate Skill

Delegate tasks to the OpenAI Codex CLI via `codex exec`. Claude Code acts as the orchestrator: it determines the appropriate sandbox level, runs `codex exec`, and summarizes the results.

## When to use

- The user explicitly invokes `/codex-delegate`
- The user asks to delegate a task to Codex in natural language (e.g. "codexにやらせて", "codexで実装して", "delegate this to codex")

## Execution flow

### 1. Determine sandbox level

Analyze the user's task and select the sandbox mode:

| Task type | Sandbox flag | Examples |
|-----------|-------------|----------|
| Read-only investigation | `-s read-only` | Code search, explanation, review, analysis |
| File creation/modification | `-s workspace-write` | Writing code, creating files, refactoring |

If ambiguous, default to `-s workspace-write` — it is safe (scoped to the workspace and /tmp) and avoids failures from write-blocked operations.

### 2. Determine model

- Default: omit the `-m` flag (uses the model from the user's codex config)
- If the user explicitly requests a specific model (e.g. "gpt-5.4で", "use gpt-5.4-mini"), pass it via `-m <model>`

### 3. Build and run the command

```
codex exec -s <sandbox> [-m <model>] "<prompt>"
```

**Always run with `run_in_background: true`** in the Bash tool call. Codex tasks can take significant time and the Bash timeout (max 10min) is insufficient. Background execution has no timeout and sends a notification on completion.

Rules for constructing the prompt:
- Pass the user's intent as-is — do not over-interpret or add unnecessary constraints
- If the user's request requires context about the current codebase, include relevant details (current directory, file structure, etc.) in the prompt
- Quote the prompt with double quotes; escape any inner double quotes

### 3a. Review tasks

When the task is a code review (and the user has NOT specified an output location), instruct Codex to write the review to a file under `/tmp/codex-reviews/`. Include this in the prompt:

```
Write the review result as a Markdown file to /tmp/codex-reviews/<descriptive-name>-<YYYYMMDD-HHmmss>.md
```

Use `-s workspace-write` so Codex can write to `/tmp`. After completion, read the output file and summarize it to the user with the file path.

### 4. Handle the result

- **Summarize** the output: what Codex did, what files were changed/created, and any notable output
- If Codex produced a diff, highlight the key changes
- If Codex failed, explain why and suggest alternatives (e.g. different sandbox level, rephrased prompt)
- Do NOT echo the raw codex output verbatim — provide a concise summary

### 5. Verify (when applicable)

After file-write tasks, read the created/modified files to confirm the changes were applied correctly.

## Important notes

- `codex exec` reads from stdin if no prompt argument is given. Always pass the prompt as an argument to avoid hanging.
- The `--full-auto` and `--dangerously-bypass-approvals-and-sandbox` flags must NOT be used.
- If `codex` is not found in PATH, inform the user and suggest installing it.

## Example invocations

```bash
# Read-only: code investigation
codex exec -s read-only "Explain the authentication flow in this codebase"

# Write: create a file
codex exec -s workspace-write "Create a Python script that reads CSV files and outputs JSON"

# Write with model override
codex exec -s workspace-write -m gpt-5.4-mini "Refactor the database module to use connection pooling"

# Review: output to /tmp
codex exec -s workspace-write "Review the recent changes for potential bugs. Write the review as Markdown to /tmp/codex-reviews/recent-changes-20260617-141000.md"
```
