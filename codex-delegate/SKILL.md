---
name: codex-delegate
description: Delegate tasks to OpenAI Codex CLI (codex exec). Use when the user asks to delegate work to Codex, or mentions "codex" in the context of task delegation (e.g. "codexに任せて", "codexでやって", "codexに委任", "delegate to codex", "let codex handle it", "use codex for this").
---

# Codex Delegate Skill

Delegate tasks to the OpenAI Codex CLI via `codex exec`. Claude Code acts as the orchestrator: it determines the appropriate sandbox level, runs `codex exec`, and summarizes the results. When the `orca-cli` skill's CLI is available and Orca is running, the invocation is routed through an Orca terminal running the interactive `codex` TUI instead of headless `codex exec` in a raw Bash process; Orca recognizes the interactive TUI as an agent CLI and surfaces it as a live agent session in its GUI (see §0/§3b).

## When to use

- The user explicitly invokes `/codex-delegate`
- The user asks to delegate a task to Codex in natural language (e.g. "codexにやらせて", "codexで実装して", "delegate this to codex")

## Execution flow

### 0. Determine execution surface (Orca vs. plain Bash)

Check whether the `orca` CLI is available and Orca is currently running:

```bash
command -v orca || command -v orca-ide
orca status --json
```

- If the CLI is not found, or `orca status` reports Orca is not running, use the plain Bash execution path (§3).
- If the CLI is available and Orca is running, route the invocation through an Orca terminal instead (§3b). This launches an interactive `codex` TUI (not headless `codex exec`) in that terminal; Orca detects it as an agent CLI and shows it as a live agent session in its GUI, instead of running invisibly in a background Bash process.
- Do not launch Orca (`orca open`) just to enable this — only route through Orca when it is already running. Otherwise fall back to §3 without asking the user.
- Exception: git-diff review tasks (§3a) always use the headless `codex exec review` path via plain Bash, even when Orca is running — `review` is an `exec` subcommand with no interactive-TUI equivalent, so Orca would not surface it as an agent session anyway.

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
- If the user explicitly requests a specific model (e.g. "gpt-5.4で", "use gpt-5.4-mini"), pass it via `-m <model>`
- This default applies to the plain-Bash `codex exec` path (§3). For Orca-routed TUI execution (§3b), omit `-m` by default and let `~/.codex/config.toml` govern the model — see the "Flag differences: TUI vs `exec`" note in §3b.

### 2a. Determine reasoning effort

Always pass `-c model_reasoning_effort=<effort>`. Default is `medium`; adjust it to the task's difficulty:

| Effort | When |
|--------|------|
| `low` | Simple, mechanical tasks: renames, small fixes with a known cause, boilerplate generation, formatting, straightforward lookups |
| `medium` (default) | Typical implementation and investigation tasks; use when difficulty is unclear |
| `high` | Hard tasks: debugging with an unknown root cause, large or cross-cutting refactors, subtle logic (concurrency, edge-case-heavy code), thorough code reviews |

- If the user explicitly requests a level (e.g. "highで", "effort low"), that always wins over the difficulty-based choice
- These rules apply to the plain-Bash `codex exec` path (§3). For Orca-routed TUI execution (§3b), omit the flag by default and let `~/.codex/config.toml` govern reasoning effort — see the "Flag differences: TUI vs `exec`" note in §3b.

### 2b. Determine web search

- Default: omit — no live web search.
- Enable when the task needs current/external information (research, fact-checking, latest docs/news, "調べて", "最新", "web検索"). Pass the `--search` flag, which turns on the native Responses `web_search` tool.
- `--search` is a top-level flag and MUST come before the `exec` subcommand: `codex --search exec ...`. Placing it after `exec` (`codex exec --search`) errors with "unexpected argument '--search'".

### 3. Build and run the command (plain Bash — when Orca is not used, per §0)

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

### 3a. Review tasks

When the task is a code review of changes in a git repository, use the dedicated `review` subcommand instead of a hand-written review prompt:

```
codex exec review <target> [-o <output-file>] ["<custom review instructions>"] < /dev/null
```

Pick the review target:

| Flag | Reviews |
|------|---------|
| `--uncommitted` | Staged, unstaged, and untracked changes |
| `--base <branch>` | Changes against a base branch (PR-style review) |
| `--commit <SHA>` | Changes introduced by a specific commit |

Notes:

- `review` runs in a read-only sandbox automatically — there is no `-s` flag, and the §1/§2a sandbox/effort defaults do not apply. Only pass `-m` or `-c` flags when the user explicitly asks for them.
- Unless the user specified an output location, pass `-o /tmp/codex-reviews/<descriptive-name>-<YYYYMMDD-HHmmss>.md` (create the directory first with `mkdir -p /tmp/codex-reviews`) so the final review is written to a file. After completion, read the file and summarize it to the user with the file path.
- Pass review-focus requests (e.g. "セキュリティ観点で") as the optional prompt argument.
- Findings come back with priority labels ([P1], [P2], …) and `file:line` locations — preserve these in the summary.
- The stdin rule (§3) and `run_in_background: true` apply here as usual.
- `review` is headless-only: run it via the plain-Bash path even when Orca is available (see §0). It has no interactive-TUI equivalent, so §3b does not apply.
- For review requests that are NOT about a git diff (e.g. "review this file/design doc"), the `review` subcommand does not apply — fall back to a regular `codex exec -s read-only` prompt (which may route through Orca per §0).

### 3b. Orca-routed execution (when available, per §0)

Instead of running `codex exec` directly via the Bash tool, launch the interactive `codex` TUI in a terminal in the *current* Orca worktree. Orca only recognizes the interactive TUI as an agent CLI and surfaces it as a live session in its GUI; a headless `codex exec` invocation is treated as an ordinary shell command and does **not** show up as an agent session, so do not route `codex exec` through Orca for this purpose.

- Create the terminal running the interactive TUI:

```bash
orca terminal create --worktree active --title "codex-delegate" --command "codex [flags]" --json
```

  Use `--worktree active` — delegation acts on the current checkout, matching the plain-Bash path. Do not create a new worktree/checkout for this (that would be a handoff, a different workflow covered by the `orca-cli` skill). `--command` runs bare `codex`, optionally with flags (see "Flag differences: TUI vs `exec`" below) — no subcommand and no prompt on the command line; the prompt is sent separately below. **Do not append `< /dev/null`** — this is the opposite of the §3/"Important notes" rule: that stdin-EOF workaround exists because headless `codex exec` reads stdin for extra prompt input and hangs waiting for EOF, whereas the interactive TUI runs on a PTY and needs stdin to stay open to receive `terminal send` input; redirecting it from `/dev/null` breaks the TUI on startup. Capture the returned terminal handle from the JSON output.

- Wait for the TUI to finish starting up:

```bash
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 30000 --json
```

- Send the prompt as terminal input, not as a command-line argument — quoting a long prompt through `--command` gets unwieldy and error-prone:

```bash
orca terminal send --terminal <handle> --text "<prompt>" --enter --json
```

  Note: the startup `tui-idle` can be satisfied while the TUI is still initializing (model shows "loading", MCP servers still starting), so a send issued right after it may interleave with startup rendering — observed in practice as stray characters mixed into the composer line, though the prompt itself still got through and was answered correctly. If the prompt must arrive clean, insert a short `sleep 5` between the startup wait and `terminal send`, then confirm via `orca terminal read` that the sent prompt was accepted intact.

- Wait for completion. The TUI process never exits, so wait on `--for tui-idle`, not `--for exit`. Immediately after `terminal send`, Orca can report `tui-idle` before Codex has actually started working, so insert a short sleep before waiting. Run this via the Bash tool with `run_in_background: true`, since Codex tasks can run long and this keeps the main loop free:

```bash
sleep 10 && orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 3600000 --json
```

- Read the output once idle:

```bash
orca terminal read --terminal <handle> --json
```

  `tui-idle` does **not** necessarily mean the task is complete — Codex may be paused on an approval prompt waiting for input. Inspect the read output: if it shows an approval prompt, decide on a response, send it with `orca terminal send`, and go back to the "wait for completion" step above. Once the output confirms the task actually finished, continue with §4/§5. (Git-diff reviews never reach this path — they run headless via §3a.)

- **Close the terminal after the task completes.** Once completion is confirmed and the results have been read and summarized (§4/§5), close the codex session with `orca terminal close --terminal <handle> --json` so finished sessions don't pile up in Orca's GUI. Exceptions — leave it open and tell the user when: the task failed or ended ambiguously (the session is needed for diagnosis), it is blocked on an approval prompt awaiting a decision, follow-up work in the same session is already planned, or the user asked to keep it.

- Terminal handles are runtime-scoped and can go stale (`terminal_handle_stale` has been observed in practice). If a call fails with that error, re-fetch the handle with `orca terminal list --json` and retry.

#### Flag differences: TUI vs `exec`

- The interactive TUI takes the form `codex [OPTIONS] [PROMPT]` — there is no `exec` subcommand. `--search` is an ordinary option here; unlike the `exec` path (§2b), there is no subcommand-ordering constraint to worry about.
- `-s <sandbox>`, `-m <model>`, and `-c key=value` behave the same as in `exec`.
- **Important**: the interactive TUI honors the user's `~/.codex/config.toml` settings (model, reasoning effort, sandbox, approval policy) as-is. Because of this, the `exec`-path defaults from §2 (omit `-m`) and §2a (always pass a difficulty-based `-c model_reasoning_effort`) do **not** carry over — for Orca-routed TUI invocations, the default is to pass **no** model/effort flags and let the user's config decide. Only add flags when there's an explicit reason to deviate: the user requested a specific model/effort, the task needs network access (same `-c` flags as §1a), or a read-only investigation should be constrained with `-s read-only`.
- Whether an approval prompt appears depends on the config's `approval_policy`. Watch for it and respond as described in the "read the output" step above.

### 4. Handle the result

- **Summarize** the output: what Codex did, what files were changed/created, and any notable output
- If Codex produced a diff, highlight the key changes
- If Codex failed, explain why and suggest alternatives (e.g. different sandbox level, rephrased prompt)
- Do NOT echo the raw codex output verbatim — provide a concise summary

### 5. Verify (when applicable)

After file-write tasks, read the created/modified files to confirm the changes were applied correctly.

## Important notes

- **Always append `< /dev/null` to close stdin** (see §3). `codex exec` reads stdin for extra prompt input even when a prompt argument is given; under `run_in_background: true` stdin never reaches EOF, so codex hangs at `Reading additional input from stdin...`. Passing the prompt as an argument is necessary but **not sufficient** — the `< /dev/null` redirect is what prevents the hang. This applies to headless `codex exec` only (§3, and §3a review tasks, which run through `exec`). **Never redirect stdin for the interactive TUI used in Orca-routed execution (§3b)** — it needs stdin to stay open on the PTY to receive `terminal send` input, and `< /dev/null` breaks it on startup.
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
codex exec -s workspace-write -m gpt-5.4-mini "Refactor the database module to use connection pooling" < /dev/null

# Simple mechanical task: lower the reasoning effort
codex exec -s workspace-write -c model_reasoning_effort=low "Rename the function getUserData to fetchUserProfile across the codebase" < /dev/null

# Hard task (unknown root cause): raise the reasoning effort
codex exec -s workspace-write -c model_reasoning_effort=high "The test suite fails intermittently on CI but passes locally. Find the root cause and fix it" < /dev/null

# Web search: research/fact-checking task (--search must precede exec)
codex --search exec -s read-only "Look up the latest Next.js release notes and summarize breaking changes" < /dev/null

# Review: uncommitted changes, result written to /tmp (mkdir -p /tmp/codex-reviews first)
codex exec review --uncommitted -o /tmp/codex-reviews/uncommitted-20260617-141000.md < /dev/null

# Review: PR-style against a base branch, with a custom focus
codex exec review --base main -o /tmp/codex-reviews/pr-vs-main-20260617-141000.md "Focus on security issues" < /dev/null

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

Orca-routed (§3b), when the `orca` CLI is available and running. Note the interactive TUI has no `exec` subcommand, no prompt argument, and no `< /dev/null`:

```bash
# 1. Create the terminal running the interactive TUI (no subcommand, no prompt, no < /dev/null)
orca terminal create --worktree active --title "codex-delegate" --command "codex" --json
# -> capture terminalHandle from the JSON result

# 2. Wait for the TUI to finish starting up
orca terminal wait --terminal <terminalHandle> --for tui-idle --timeout-ms 30000 --json

# 3. Send the prompt as terminal input (not a command-line argument)
orca terminal send --terminal <terminalHandle> --text "Refactor the database module to use connection pooling" --enter --json

# 4. Wait for completion in the background (run_in_background: true); a short sleep first
#    avoids observing tui-idle before Codex has actually started working
sleep 10 && orca terminal wait --terminal <terminalHandle> --for tui-idle --timeout-ms 3600000 --json

# 5. Once notified, read what happened. tui-idle may mean "waiting on an approval prompt"
#    rather than "done" -- if so, send a response with terminal send and repeat step 4.
orca terminal read --terminal <terminalHandle> --json

# 6. After confirming completion and summarizing the results, close the session
#    (skip this only for the exceptions listed in §3b: failure, pending approval,
#    planned follow-up in the same session, or an explicit user request to keep it)
orca terminal close --terminal <terminalHandle> --json
```
