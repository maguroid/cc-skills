#!/usr/bin/env bash
# codex-run.sh — robust wrapper for delegating a prompt to `codex exec`.
#
# Why this exists: hand-built `codex exec` invocations repeatedly broke two ways —
#   1) missing `< /dev/null`  => codex blocks forever at
#      "Reading additional input from stdin..." under background execution;
#   2) piping through `| tail` => output buffered, nothing readable until (never) EOF.
# This wrapper hardcodes `< /dev/null`, writes the FULL transcript to a log file,
# and prints only a short tail + the exit code. Launch it with run_in_background:true.
#
# The prompt is read from a FILE (not an argument) to avoid shell-quoting bugs on
# long/multiline prompts — another recurring failure. Write the prompt to a temp
# .md first, then pass --prompt-file.
#
# Usage:
#   codex-run.sh --prompt-file <path> [--out <log>] [--dir <workdir>]
#                [--sandbox read-only|workspace-write] [--effort low|medium|high]
#                [--model <m>] [--network] [--search] [--skip-git-check] [--dry-run]
#
# Flag choices (sandbox / effort / model / network / search) are decided per the
# skill's §1–§2b; this wrapper only applies them correctly. For the `review`
# subcommand, use the skill's documented invocation (this wrapper targets
# prompt-based `exec`).
set -euo pipefail

usage() { sed -n '15,18p' "$0" | sed 's/^# \{0,1\}//'; }

prompt_file=""; out=""; dir=""; sandbox="workspace-write"; effort="medium"
model=""; network=0; search=0; skipgit=0; dryrun=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) prompt_file="${2:?--prompt-file needs a value}"; shift 2;;
    --out)         out="${2:?--out needs a value}"; shift 2;;
    --dir)         dir="${2:?--dir needs a value}"; shift 2;;
    --sandbox)     sandbox="${2:?--sandbox needs a value}"; shift 2;;
    --effort)      effort="${2:?--effort needs a value}"; shift 2;;
    --model)       model="${2:?--model needs a value}"; shift 2;;
    --network)     network=1; shift;;
    --search)      search=1; shift;;
    --skip-git-check) skipgit=1; shift;;
    --dry-run)     dryrun=1; shift;;
    -h|--help)     usage; exit 0;;
    *) echo "codex-run: unknown arg: $1" >&2; usage >&2; exit 2;;
  esac
done

command -v codex >/dev/null 2>&1 || { echo "codex-run: codex not found in PATH" >&2; exit 127; }
[[ -n "$prompt_file" && -f "$prompt_file" ]] || { echo "codex-run: --prompt-file must point to an existing file" >&2; exit 2; }
[[ -n "$out" ]] || out="${TMPDIR:-/tmp}/codex-run-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$out")"

cmd=(codex)
[[ $search -eq 1 ]] && cmd+=(--search)
cmd+=(exec)
[[ $skipgit -eq 1 ]] && cmd+=(--skip-git-repo-check)
cmd+=(-s "$sandbox" -c "model_reasoning_effort=$effort")
[[ -n "$model" ]] && cmd+=(-m "$model")
[[ -n "$dir" ]] && cmd+=(-C "$dir")
[[ $network -eq 1 ]] && cmd+=(-c "sandbox_workspace_write.network_access=true")
cmd+=("$(cat "$prompt_file")")

if [[ $dryrun -eq 1 ]]; then
  printf 'DRY-RUN cmd:'; printf ' %q' "${cmd[@]}"; printf ' < /dev/null\n'
  echo "log would be: $out"
  exit 0
fi

{ echo "=== codex-run $(date '+%Y-%m-%dT%H:%M:%S') ==="; printf 'cmd:'; printf ' %q' "${cmd[@]}"; printf ' < /dev/null\n'; echo "=== output ==="; } > "$out"
set +e
"${cmd[@]}" < /dev/null >> "$out" 2>&1
rc=$?
set -e
echo "codex exit: $rc"
echo "log: $out"
echo "--- last 25 lines ---"
tail -n 25 "$out"
exit "$rc"
