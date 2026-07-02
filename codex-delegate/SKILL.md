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

- Default: `medium` — always pass `-c model_reasoning_effort=medium` unless the user specifies otherwise
- If the user explicitly requests a different level (e.g. "highで", "effort low"), use that value instead
- This default applies to the plain-Bash `codex exec` path (§3). For Orca-routed TUI execution (§3b), omit the flag by default and let `~/.codex/config.toml` govern reasoning effort — see the "Flag differences: TUI vs `exec`" note in §3b.

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

- Wait for completion. The TUI process never exits, so wait on `--for tui-idle`, not `--for exit`. Immediately after `terminal send`, Orca can report `tui-idle` before Codex has actually started working, so insert a short sleep before waiting. Run this via the Bash tool with `run_in_background: true`, since Codex tasks can run long and this keeps the main loop free:

```bash
sleep 10 && orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 3600000 --json
```

- Read the output once idle:

```bash
orca terminal read --terminal <handle> --json
```

  `tui-idle` does **not** necessarily mean the task is complete — Codex may be paused on an approval prompt waiting for input. Inspect the read output: if it shows an approval prompt, decide on a response, send it with `orca terminal send`, and go back to the "wait for completion" step above. Once the output confirms the task actually finished, continue with §4/§5. If the task is a review (§3a), Codex still writes its Markdown output to `/tmp/codex-reviews/...`; read that file once completion is confirmed, same as the plain-Bash path.

- Leave the terminal (codex session) open after the task completes. Do not close it — keeping it open is what lets the user see the session in Orca's GUI, which is the point of routing through Orca in the first place.

- Terminal handles are runtime-scoped and can go stale (`terminal_handle_stale` has been observed in practice). If a call fails with that error, re-fetch the handle with `orca terminal list --json` and retry.

#### Flag differences: TUI vs `exec`

- The interactive TUI takes the form `codex [OPTIONS] [PROMPT]` — there is no `exec` subcommand. `--search` is an ordinary option here; unlike the `exec` path (§2b), there is no subcommand-ordering constraint to worry about.
- `-s <sandbox>`, `-m <model>`, and `-c key=value` behave the same as in `exec`.
- **Important**: the interactive TUI honors the user's `~/.codex/config.toml` settings (model, reasoning effort, sandbox, approval policy) as-is. Because of this, the `exec`-path defaults from §2 (omit `-m`) and §2a (always pass `-c model_reasoning_effort=medium`) do **not** carry over — for Orca-routed TUI invocations, the default is to pass **no** model/effort flags and let the user's config decide. Only add flags when there's an explicit reason to deviate: the user requested a specific model/effort, the task needs network access (same `-c` flags as §1a), or a read-only investigation should be constrained with `-s read-only`.
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

# Web search: research/fact-checking task (--search must precede exec)
codex --search exec -s read-only "Look up the latest Next.js release notes and summarize breaking changes" < /dev/null

# Review: output to /tmp
codex exec -s workspace-write "Review the recent changes for potential bugs. Write the review as Markdown to /tmp/codex-reviews/recent-changes-20260617-141000.md" < /dev/null

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
```
