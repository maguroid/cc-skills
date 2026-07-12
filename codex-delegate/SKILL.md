---
name: codex-delegate
description: Delegate tasks to OpenAI Codex CLI (codex exec). Use when the user asks to delegate work to Codex, or mentions "codex" in the context of task delegation (e.g. "codexに任せて", "codexでやって", "codexに委任", "delegate to codex", "let codex handle it", "use codex for this").
---

# Codex Delegate Skill

Delegate tasks to the OpenAI Codex CLI via `codex exec` (headless). Claude Code acts as the orchestrator: it determines the appropriate sandbox level, runs `codex exec`, and summarizes the results. Headless execution is the only path — process exit is the completion signal, so completion detection is reliable. (An Orca-routed interactive-TUI path existed until 2026-07-04 and was retired: the GUI visibility went unused, and `tui-idle` was an unreliable completion signal.)

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

### 1a. Determine network access

Both `read-only` and `workspace-write` sandboxes **block network access by default**. If the task requires network (e.g. `npm install`, `pip install`, fetching a URL, `git fetch`/`git clone`, calling an external API), enable it per-invocation with `-c` flags — no need to edit `~/.codex/config.toml`:

- Enable network: `-c sandbox_workspace_write.network_access=true`
- (Optional) Restrict to specific domains via the network proxy:
  - `-c features.network_proxy.enabled=true`
  - `-c 'features.network_proxy.domains={ "registry.npmjs.org" = "allow" }'`

Default to enabling network only when the task clearly needs it. Prefer narrowing to known domains for installs/fetches when the domains are predictable; omit the proxy restriction when the task needs broad/unknown access.

### 2. Determine model

- Default: omit the `-m` flag (uses the model from the user's codex config)
- If the user explicitly requests a specific model (e.g. "gpt-5.6-solで", "use gpt-5.6-luna"), pass it via `-m <model>`. Otherwise never hardcode a model name — the config default tracks the current model, so omitting `-m` is what keeps this skill current as models change.

### 2a. Determine reasoning effort

Always pass `-c model_reasoning_effort=<effort>`. Default is `medium`; adjust it to the task's difficulty:

| Effort | When |
|--------|------|
| `low` | Simple, mechanical tasks: renames, small fixes with a known cause, boilerplate generation, formatting, straightforward lookups |
| `medium` (default) | Typical implementation and investigation tasks; use when difficulty is unclear |
| `high` | Hard tasks: debugging with an unknown root cause, large or cross-cutting refactors, subtle logic (concurrency, edge-case-heavy code), thorough code reviews |

- If the user explicitly requests a level (e.g. "highで", "effort low"), that always wins over the difficulty-based choice

### 2b. Determine web search

- Default: omit — no live web search.
- Enable when the task needs current/external information (research, fact-checking, latest docs/news, "調べて", "最新", "web検索"). Pass the `--search` flag, which turns on the native Responses `web_search` tool.
- `--search` is a top-level flag and MUST come before the `exec` subcommand: `codex --search exec ...`. Placing it after `exec` (`codex exec --search`) errors with "unexpected argument '--search'".

### 3. Build and run the command

```
codex [--search] exec -s <sandbox> [-m <model>] -c model_reasoning_effort=<effort> [network flags] "<prompt>" < /dev/null
```

where `[network flags]` are added only for network-requiring tasks (see §1a), e.g. `-c sandbox_workspace_write.network_access=true`.

**Always run with `run_in_background: true`** in the Bash tool call. Codex tasks can take significant time and the Bash timeout (max 10min) is insufficient. Background execution has no timeout and sends a notification on completion.

**Always append `< /dev/null`.** `codex exec` reads stdin for additional prompt input *even when a prompt argument is given*. Under `run_in_background: true` the shell's stdin stays open with no EOF, so codex blocks forever — the output stalls at `Reading additional input from stdin...` and never runs. Passing the prompt as an argument is **not** enough on its own; redirecting stdin from `/dev/null` gives an immediate EOF and prevents the hang. Make `< /dev/null` part of every invocation. (To recover from a hang already in progress: `pkill -f "codex exec"`, then re-run with the redirect.)

**If the working directory is not inside a git repository (or another codex-trusted directory), add `--skip-git-repo-check`** (an `exec`-level option). Without it, codex aborts immediately with `Not inside a trusted directory and --skip-git-repo-check was not specified.`

Rules for constructing the prompt:
- Pass the user's intent as-is — do not over-interpret or add unnecessary constraints
- If the user's request requires context about the current codebase, include relevant details (current directory, file structure, etc.) in the prompt
- Quote the prompt with double quotes; escape any inner double quotes

### 3-wrapper. Preferred invocation: `scripts/codex-run.sh`

**Do not hand-assemble the `codex exec` command line.** Even with the rules above documented, hand-built invocations kept breaking on the two failure modes (missing `< /dev/null` → stdin hang; `| tail` → buffered/empty output). Call the bundled wrapper instead — it hardcodes `< /dev/null`, writes the full transcript to a log file, and prints only a short tail + exit code, so those mistakes are impossible.

The wrapper lives beside this file at `scripts/codex-run.sh` (resolve its absolute path from the skill directory). Decide the flags per §1–§2b, write the prompt to a temp file (avoids shell-quoting bugs on long/multiline prompts), then launch **with `run_in_background: true`**:

```bash
# write the prompt to a file first
cat > /tmp/codex-prompt.md <<'EOF'
<the full prompt, multiline is fine, no escaping needed>
EOF

<skill-dir>/scripts/codex-run.sh \
  --prompt-file /tmp/codex-prompt.md \
  --dir <workdir> \
  --sandbox workspace-write \
  --effort medium \
  [--model <m>] [--network] [--search] [--skip-git-check] \
  [--out /tmp/codex-run.log]
```

Flag mapping: `--sandbox` (§1), `--network` (§1a, broad access), `--model` (§2), `--effort` (§2a), `--search` (§2b), `--skip-git-check` (§3, non-git workdir). For domain-restricted network or the `review` subcommand (§3a), the wrapper does not cover those — use the documented raw invocation (still ending in `< /dev/null`). When the wrapper finishes, read its `log:` file if you need the full transcript; otherwise the printed tail + exit code is enough to summarize.

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

### 4. Handle the result

- **Summarize** the output: what Codex did, what files were changed/created, and any notable output
- If Codex produced a diff, highlight the key changes
- If Codex failed, explain why and suggest alternatives (e.g. different sandbox level, rephrased prompt)
- Do NOT echo the raw codex output verbatim — provide a concise summary

### 5. Verify (when applicable)

After file-write tasks, read the created/modified files to confirm the changes were applied correctly.

## Important notes

- **Always append `< /dev/null` to close stdin** (see §3). `codex exec` reads stdin for extra prompt input even when a prompt argument is given; under `run_in_background: true` stdin never reaches EOF, so codex hangs at `Reading additional input from stdin...`. Passing the prompt as an argument is necessary but **not sufficient** — the `< /dev/null` redirect is what prevents the hang.
- The `--full-auto` and `--dangerously-bypass-approvals-and-sandbox` flags must NOT be used.
- If `codex` is not found in PATH, inform the user and suggest installing it.

## Example invocations

Every invocation ends with `< /dev/null` (close stdin — see §3) and is launched with `run_in_background: true`.

```bash
# Read-only: code investigation
codex exec -s read-only "Explain the authentication flow in this codebase" < /dev/null

# Write: create a file
codex exec -s workspace-write "Create a Python script that reads CSV files and outputs JSON" < /dev/null

# Write with model override
codex exec -s workspace-write -m gpt-5.6-luna "Refactor the database module to use connection pooling" < /dev/null

# Simple mechanical task: lower the reasoning effort
codex exec -s workspace-write -c model_reasoning_effort=low "Rename the function getUserData to fetchUserProfile across the codebase" < /dev/null

# Hard task (unknown root cause): raise the reasoning effort
codex exec -s workspace-write -c model_reasoning_effort=high "The test suite fails intermittently on CI but passes locally. Find the root cause and fix it" < /dev/null

# Web search: research/fact-checking task (--search must precede exec)
codex --search exec -s read-only "Look up the latest Next.js release notes and summarize breaking changes" < /dev/null

# Review: uncommitted changes, result written to /tmp (mkdir -p /tmp/codex-reviews first)
codex exec review --uncommitted -o /tmp/codex-reviews/uncommitted-20260617-141000.md < /dev/null

# Review: PR-style against a base branch (no custom instructions — incompatible with target flags)
codex exec review --base main -o /tmp/codex-reviews/pr-vs-main-20260617-141000.md < /dev/null

# Review: uncommitted scope with a custom focus (prompt only works WITHOUT a target flag)
codex exec review -o /tmp/codex-reviews/security-20260617-141000.md "Focus on security issues" < /dev/null

# Network: install dependencies (broad access)
codex exec -s workspace-write -c sandbox_workspace_write.network_access=true "Install dependencies and make the build pass" < /dev/null

# Network: restricted to a known domain
codex exec -s workspace-write \
  -c sandbox_workspace_write.network_access=true \
  -c features.network_proxy.enabled=true \
  -c 'features.network_proxy.domains={ "registry.npmjs.org" = "allow" }' \
  "Run npm install" < /dev/null

# Multi-line prompt (heredoc-style): the redirect still goes at the very end
codex exec -s workspace-write -c model_reasoning_effort=medium "Download the brand SVG logos into src/assets/logos/ and summarize their licenses" < /dev/null
```
