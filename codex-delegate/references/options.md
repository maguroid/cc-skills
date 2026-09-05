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
