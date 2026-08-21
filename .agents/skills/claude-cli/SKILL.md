---
name: claude-cli
description: "Delegate the full software task lifecycle to Claude Code CLI across Windows, macOS, and Linux. Use when the user wants Codex to act only as leader and reviewer while Claude investigates the repository, proposes a plan, implements only after explicit user approval, runs validation, and repairs review findings with minimal Codex token usage."
---

# Claude Code CLI

Use Claude Code CLI as the worker. Treat the user as Manager and Codex as Leader and Reviewer.

## Enforce role boundaries

- Let the Manager define scope, resolve business decisions, approve the reviewed plan, and authorize actions outside normal implementation scope.
- Let Codex translate the request into precise Claude prompts, enforce repository rules and approval gates, review plans and diffs, and report results.
- Let Claude investigate, plan, edit approved production code, run checks, repair findings, and complete repository-required post-change work.
- Do not replace Claude CLI with a Codex subagent.
- Do not implement production code directly with Codex when Claude can do it.
- Allow Codex only focused local inspection or verification when Claude's evidence is missing, inconsistent, ambiguous, or high-risk.
- Treat current repository source as the source of truth.

## Launch Claude correctly

Always set the execution working directory to the repository root. Do not launch elsewhere and rely on `cd` inside the prompt. Quote paths when needed and use syntax appropriate for the active shell.

Before the first delegation in an environment, verify Claude is available:

Windows PowerShell:

```powershell
Get-Command claude
claude --version
```

macOS/Linux:

```bash
command -v claude
claude --version
```

If Claude cannot be resolved, stop and report the blocker. Do not substitute another coding agent.

Use this worker configuration unless the Manager explicitly selects another:

```text
MODEL: sonnet
EFFORT: high
```

Pass `--model sonnet --effort high` on every invocation. If the requested model or effort is unavailable, stop rather than silently substituting.

Use print mode for delegated work. Apply a host-side timeout or process monitor; a timeout is only a safety bound and never proof of completion.

## Follow the mandatory lifecycle

### 1. Delegate investigation and planning

Create a concise, technically complete planning brief that includes:

- desired outcome and business requirements;
- current decisions, constraints, exclusions, paths, and artifacts;
- instructions to discover and follow repository guidance;
- instructions to inspect the current source and architecture;
- instructions not to edit production files or tests and not to commit or push;
- the required structured response below.

Launch a uniquely named planning session with read-only planning permissions:

```text
claude --name "<task-name>" --model sonnet --effort high --permission-mode plan -p "<planning brief>"
```

Require Claude to finish with:

```text
PLANNING_STATUS: COMPLETE | BLOCKED
PLAN_ARTIFACT: INLINE
PLAN_SUMMARY: <short summary>
OPEN_DECISIONS: <none or explicit manager decisions>
```

Require the plan to cover:

- exact files expected to change and relevant files inspected;
- current behavior and defect root cause when applicable;
- architecture and exact implementation steps;
- affected state/data flow and API or persistence changes;
- authorization, security, concurrency, and compatibility effects;
- error handling, logging, and observability;
- existing tests and manual cases to run;
- exact validation, build, and test commands;
- exclusions, assumptions, risks, and completion criteria.

Require Claude to distinguish verified repository facts from assumptions and identify anything important it could not verify.

### 2. Review and repair the plan

Review Claude's plan against only the plan, repository instructions, narrowly relevant source and configuration, and directly relevant existing tests.

Check file accuracy, architecture, minimal scope, business logic, state and data models, API contracts, authentication and authorization, validation and injection risks, secrets and sensitive data, database constraints and transactions, concurrency, compatibility and migrations, platform versions, error handling, observability, verification quality, stale assumptions, and completion criteria.

Do not silently rewrite a materially incorrect plan. Return material technical findings to the same Claude session and require a repository-evidence-based revision. Repeat until sound. Formatting-only normalization may be done by Codex.

Resume an exact session when possible:

```text
claude --resume "<session-name-or-id>" --model sonnet --effort high -p "<plan review findings>"
```

Do not use `-c` blindly when several project sessions may exist.

### 3. Stop for Manager approval

Present the reviewed implementation summary, expected files, important decisions, assumptions, exclusions, risks, verification strategy, and open business decisions. Then stop.

Do not edit production code or launch Claude with edit-enabled permissions until the Manager explicitly approves. Approval may be expressed as `oke làm`, `thực hiện`, `duyệt`, `implement`, or `go ahead`. Questions, explanation requests, and plan changes are not approval. If scope changes materially, revise the plan and obtain fresh approval.

### 4. Delegate approved implementation

Resume the same session whenever possible:

```text
claude --resume "<session-name-or-id>" --model sonnet --effort high --dangerously-skip-permissions -p "<approved implementation brief>"
```

The permission bypass removes interactive prompts only. It does not authorize broader scope or destructive/external actions.

Tell Claude to:

- implement only the approved plan and Manager-approved scope;
- inspect current files immediately before editing;
- preserve unrelated user work;
- make the smallest correct production change using existing architecture;
- avoid speculative cleanup, unnecessary refactoring, and dependency upgrades;
- follow repository instructions;
- run relevant existing tests, builds, lint, formatting, static analysis, type checks, and focused security checks;
- complete every repository-defined post-change step;
- provide exact evidence.

Treat test files as read-only unless the Manager separately authorizes test changes. Never create, edit, delete, rename, move, regenerate, or auto-fix tests, fixtures, snapshots, golden files, or baselines without that approval. If a test appears stale or contradictory, report it instead of changing it.

Repository-mandated changelogs, generated metadata, manifests, version metadata, formatting, validation, and directly required documentation are part of implementation. Claude must report `BLOCKED` if a mandatory step cannot be completed.

Unless explicitly authorized, never let Claude commit, push, create or update a pull request, publish, deploy, release, upload builds, alter live databases, execute production migrations, delete user data, perform destructive cleanup, reset unrelated changes, discard local work, or update unrelated documentation.

Require this final implementation format:

```text
IMPLEMENTATION_STATUS: COMPLETE | BLOCKED

TEST_STATUS:
- <command>: PASS | FAIL | NOT_RUN

POST_CHANGE_STATUS:
- <required repository step>: PASS | FAIL | NOT_REQUIRED

FILES_CHANGED:
- <path>

IMPLEMENTATION_SUMMARY:
<short factual summary>

REVIEW_NOTES:
<known limitations, residual risks, environment blockers, or none>
```

### 5. Monitor actual completion

Treat Claude's implementation as complete only when all are true:

1. The process exited normally.
2. The required completion marker was emitted.
3. `IMPLEMENTATION_STATUS` is `COMPLETE`.
4. Relevant builds and tests finished with recorded results.
5. Diff and changed-file evidence are available.
6. Mandatory repository post-change steps finished.
7. No relevant Claude or background tasks remain pending.

Idle, silence, timeout, partial output, process crash, non-zero unexpected exit, missing markers, `BLOCKED`, unfinished tests, unfinished repository workflow, or unreviewed diffs all mean incomplete work.

### 6. Review the implementation

Review the approved plan, scoped diff, changed files, relevant context, Claude's command evidence, test/build results, and post-change evidence. Avoid broad rediscovery unless the evidence is insufficient.

Check for missing requirements, unintended scope, incorrect logic, edge cases, regressions, stale assumptions, unsafe null handling, concurrency and memory issues, transaction problems, authentication and authorization errors, injection, secret or sensitive-data exposure, contract mismatch, poor error handling or observability, debug code, temporary/generated junk, unrelated edits, unauthorized documentation or tests, commits or pushes, and incomplete repository workflow.

Do not silently patch production code.

### 7. Return verified defects to Claude

For every material finding, resume the same session with a precise repair request:

```text
SEVERITY: blocker | high | medium | low
FILE_OR_BEHAVIOR: <path or behavior>
EVIDENCE: <what is wrong>
EXPECTED_RESULT: <correct behavior>
REQUIRED_FIX: <required outcome, not speculative implementation>
REGRESSION_CHECK: <existing test or verification>
SCOPE_BOUNDARY: <what must not change>
```

Use:

```text
claude --resume "<session-name-or-id>" --model sonnet --effort high --dangerously-skip-permissions -p "<review findings>"
```

Require Claude to re-inspect current code, fix only verified findings, preserve unrelated work, rerun affected checks, repeat mandatory post-change steps, and return the same structured completion format. Review again. If repair needs a new business decision or broader scope, stop and ask the Manager.

### 8. Report completion

Report completion only when the approved implementation is present, Claude reported `COMPLETE`, Codex reviewed the diff, required checks passed or legitimate environment limitations are explicit, mandatory repository steps passed, no blocking findings remain, and no unauthorized changes remain.

Summarize what changed, key decisions, changed files, commands and results, repaired review findings, residual non-blocking risks, environment limitations, and relevant artifacts. Never claim a check passed without evidence or convert an incomplete state into completion.

## Optimize delegation

- Delegate discovery, detailed planning, production edits, checks, and repairs to Claude.
- Consume only focused evidence needed to lead and review.
- Reuse the same Claude session for the task.
- Avoid repeated broad scans or expensive checks without cause.
- Keep prompts focused and never include secrets unless strictly required and explicitly authorized.

The operating sequence is:

```text
Manager request
  -> Claude investigation and plan
  -> Codex technical review
  -> Claude plan repair as needed
  -> Manager approval
  -> Claude implementation and validation
  -> Codex diff review
  -> Claude repair as needed
  -> Codex final verification and report
```

Never skip the approval boundary between planning and production-code modification.
