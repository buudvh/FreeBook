---
name: antigravity
description: "Delegates the full software task lifecycle to Antigravity CLI across Windows and macOS: Antigravity investigates and proposes a plan, Codex reviews it, the user explicitly approves it, then Antigravity implements, tests, and repairs review findings. Use when the user wants Codex to act only as leader/reviewer while AGY performs repository discovery, planning, coding, testing, and fixes with minimal Codex token usage."
---

# Antigravity

Use Antigravity as the worker. The user is the manager; Codex is the leader and reviewer.

## Roles and hard boundaries

- Manager (user): defines scope, resolves business decisions, and approves the reviewed plan.
- Leader (Codex): prepares AGY prompts, reviews plans and diffs, enforces scope/security, and reports results.
- Worker (Antigravity): investigates the repository, plans, writes code, runs tests, and fixes review findings.

Do not replace AGY with a Codex subagent. Do not implement production code or routinely rerun broad test suites with Codex. Use a focused local verification only when AGY evidence is missing, inconsistent, or high risk.

## Cross-platform CLI setup

Always launch AGY with the repository root as the working directory because conversations are workspace-scoped. Prefer the execution tool's `workdir` option instead of composing a shell `cd` command.

Verify the executable before the first launch:

```powershell
# Windows PowerShell
Get-Command agy
# Fallback for a newly installed CLI before the terminal PATH is refreshed:
& "$env:LOCALAPPDATA\agy\bin\agy.exe" --help
```

```bash
# macOS zsh/bash
command -v agy
agy --help
```

Use `agy` after it resolves on PATH. Keep paths quoted. Use PowerShell syntax on Windows and POSIX shell syntax on macOS; never mix environment-variable or quoting syntax between them.

## Permission mode

This trusted workspace is explicitly authorized to run AGY without interactive permission prompts. Always include `--dangerously-skip-permissions` on every AGY session launch that can inspect, edit, or execute repository commands. Do not omit the flag or fall back to the interactive permission preset.

AGY settings are stored at:

- macOS: `~/.gemini/antigravity-cli/settings.json`
- Windows: `$env:USERPROFILE\.gemini\antigravity-cli\settings.json`

## Required model

Use `Gemini 3.6 Flash (High)` for planning, implementation, testing, and repair sessions. Pass it explicitly on every launch so the result does not depend on a user's persisted CLI default:

```text
agy --dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" ...
```

Run `agy models` before the first delegation in a new environment. If the exact model is unavailable, stop and tell the manager; do not silently substitute another model or reasoning level.

## Preferred non-interactive commands

Prefer print mode for delegation. It returns output to the host process and exits, avoiding a TUI left idle at its prompt.

```text
# Ask AGY to plan without editing production files
agy --dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --mode=plan --print-timeout=30m --print "<planning brief>"

# Implement an approved plan and automatically accept file edits
agy --dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --mode=accept-edits --print-timeout=60m --print "<approved plan and constraints>"

# Continue the newest conversation in the current workspace
agy --dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --continue --print-timeout=60m --print "<follow-up or repair request>"

# Resume an exact conversation
agy --dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --conversation <conversation-id> --print-timeout=60m --print "<follow-up or repair request>"
```

`-p` is the short alias for `--print`, and `-c` is the short alias for `--continue`. Adjust timeouts to the task; do not use a timeout as proof that work completed.

Use `--dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --prompt-interactive "<prompt>"` only when a live TUI is necessary. Use `--sandbox` when terminal containment is appropriate. Use `--add-dir <path>` only for an explicitly scoped additional directory.

## Essential TUI commands

When an interactive session is necessary, use these commands from the official CLI documentation:

| Command | Purpose |
| --- | --- |
| `?` or `/usage` | Open CLI help. |
| `@` | Insert a file path using suggestions. |
| `!<command>` | Run a terminal command directly. |
| `/planning` | Enable planning behavior for a complex task. |
| `/permissions` | Inspect or change the permission preset. |
| `/diff` | Review modified and untracked workspace files. |
| `/agents` | Monitor AGY background subagents. |
| `/tasks` | Monitor shell commands, builds, and test processes. |
| `/skills` | Inspect loaded local and global skills. |
| `/resume` | Select a prior workspace conversation. |
| `/rewind` or `/undo` | Return conversation history to an earlier message. |
| `/fork` or `/branch` | Fork conversation history; this does not isolate filesystem changes. |
| `/config` or `/settings` | Open CLI settings. |
| `/exit` | Close the TUI and return to the host shell. |

Important controls:

- `Ctrl+C` or `Esc`: cancel a stream or close the active menu.
- `Ctrl+D`: exit the CLI.
- `Esc Esc`: clear a non-streaming prompt.
- `y` / `n`: approve or reject a proposed terminal command.
- `e`: edit a proposed terminal command before approval.

Run `agy --help` and type `/usage` if the installed version differs from this reference.

## Mandatory lifecycle

### 1. Delegate planning

Turn the manager's request into a concise planning brief containing:

- outcome, constraints, exclusions, and current business decisions;
- relevant artifact and repository paths;
- repository instructions AGY must follow;
- instruction to inspect current source code as the source of truth;
- instruction not to edit production files;
- required structured completion response.

Launch AGY with `--dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --mode=plan --print`. Require:

```text
PLANNING_STATUS: COMPLETE | BLOCKED
PLAN_ARTIFACT: <absolute path or INLINE>
PLAN_SUMMARY: <short summary>
OPEN_DECISIONS: <none or explicit manager decisions>
```

The plan must identify exact files, current behavior, implementation steps, data/API/security effects, test cases, verification commands, exclusions, and completion criteria. If AGY returns an inline plan, treat captured stdout as the plan artifact.

### 2. Review and repair the plan

Review only the proposed plan and narrowly scoped source evidence. Check:

- current architecture and existing base code;
- file-level accuracy and minimal scope;
- data model, API, authorization, validation, and security;
- compatibility, migration, transaction, and concurrency risks;
- meaningful test coverage;
- stale entities, fields, APIs, assumptions, or unwanted documentation work;
- explicit completion criteria.

Send material findings back to AGY through the same conversation and require a revised plan. Repeat until it is technically sound. Codex may normalize wording, but technical changes must be rechecked by AGY against the repository.

### 3. Stop for manager approval

Present the reviewed plan, assumptions, exclusions, risks, and open decisions to the manager. End the turn and wait.

Do not start an edit-enabled session or change production code until the manager gives unambiguous approval such as `oke lam` or `thuc hien`. A request to explain or revise the plan is not approval. If scope changes, return to planning and request approval again.

### 4. Delegate implementation and testing

After approval, send AGY the exact approved plan and current constraints with `--dangerously-skip-permissions --model "Gemini 3.6 Flash (High)" --mode=accept-edits --print`. Require it to:

- change only approved files and preserve unrelated user work;
- follow repository instructions;
- run relevant tests, lint, type checks, builds, and focused security checks;
- avoid docs, commits, pushes, releases, migrations against live data, or destructive actions unless explicitly approved;
- report exact commands, outcomes, changed files, and known limitations.

Require:

```text
IMPLEMENTATION_STATUS: COMPLETE | BLOCKED
TEST_STATUS: <commands and pass/fail summary>
FILES_CHANGED: <paths>
REVIEW_NOTES: <known limitations, risks, or none>
```

### 5. Monitor real completion

Track the host process or session ID. Poll with bounded waits and report only meaningful progress.

For non-interactive print mode, completion requires:

1. the AGY process exited successfully;
2. AGY emitted `IMPLEMENTATION_STATUS: COMPLETE` rather than `BLOCKED`;
3. all reported builds and tests returned;
4. the diff and test evidence are available.

For a TUI session, also inspect `/agents` and `/tasks`. An idle prompt or silence is not completion. Close a completed TUI with `/exit` or `Ctrl+D`; use repeated `Ctrl+C` only to cancel stuck streaming or a runaway task.

### 6. Review the result

Review the approved plan, scoped diff, touched files, and raw test evidence. Check:

- plan completeness and unintended changes;
- business logic and edge cases;
- authentication, authorization, validation, injection, secrets, and data exposure;
- database constraints, transactions, concurrency, and compatibility;
- frontend/API contract consistency;
- error handling and observability;
- useful regression tests;
- generated files, debug code, and unrelated edits.

Do not silently patch production code. Do not repeat broad repository scans or full tests unless AGY evidence is insufficient.

### 7. Return defects to AGY

For each finding provide severity, file/behavior, evidence, expected result, required fix, regression test, and scope boundary. Continue the same AGY conversation when possible, then monitor and review again.

Repeat until no blocking correctness, security, test, or scope issue remains. If a business decision or new authority is required, stop and ask the manager.

### 8. Report completion

Only report completion after review passes. Summarize implementation, passed checks, repaired findings, remaining non-blocking risks, and relevant artifacts.

## Efficiency and safety

- Delegate discovery, planning, coding, testing, and repairs to AGY.
- Use `Gemini 3.6 Flash (High)` for every AGY session.
- Reuse the same workspace conversation and structured artifacts.
- Read only focused plans, diffs, touched files, and test logs.
- Never bypass the approval gate or broaden scope.
- Never commit, push, release, update docs, or delete data unless explicitly authorized.
- Treat `BLOCKED`, timeout, process crash, and missing completion markers as incomplete work.
