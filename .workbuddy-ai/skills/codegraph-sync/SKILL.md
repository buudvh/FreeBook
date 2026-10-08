---
name: codegraph-sync
description: "Ensure the CodeGraph structural index (.codegraph/) for a project exists and is up to date. Use when the user asks to initialize, sync, refresh, rebuild, or update the codegraph index (e.g. after a large git pull, branch switch, or checkout on a new machine), or when a codegraph explore/query/node command reports \"no .codegraph/ index exists ... run 'codegraph init'\". If no index exists, build one; otherwise perform an incremental sync, with a full-rebuild option and automatic stale-lock recovery."
agent_created: true
---

# CodeGraph Sync

## Overview

Ensure the CodeGraph structural index (`.codegraph/`) for a project is present
and current. This is the sanctioned way to bootstrap or refresh the index: the
script builds a fresh index when none exists, otherwise performs an incremental
sync, with a `--full` rebuild option and automatic stale-lock recovery.

## When to use

- The user asks to init / sync / refresh / rebuild / update the codegraph index.
- After a large `git pull`, branch switch, or checkout on a new machine — or
  before any heavy structural investigation (e.g. tracing call paths, impact).
- A `codegraph explore` / `query` / `node` / `status` command reports
  `no .codegraph/ index exists ... run 'codegraph init'`.

## Prerequisites

- `codegraph` CLI on PATH. Install / upgrade via `codegraph upgrade` or the
  GitHub release `install.ps1`.
- A repo root containing `codegraph.json` (optional but recommended — supplies
  the `exclude` / `deprioritize` config used by `codegraph init`).

## Workflow

1. Determine the target — the project root. Default to the current working
   directory; accept an explicit path argument.
2. Run the bundled script:

   ```bash
   # Incremental sync (index already exists), or fresh init if it does not:
   bash <skill>/scripts/sync_codegraph.sh [path]

   # Full rebuild from scratch (same result as fresh init):
   bash <skill>/scripts/sync_codegraph.sh --full [path]
   ```

   Behaviour inside the script:
   - No `.codegraph/` dir → `codegraph init --yes <path>` (build fresh index).
   - `.codegraph/` exists → `codegraph sync <path>` (incremental).
   - `--full` → `codegraph index <path>` (full rebuild).
3. Stale lock: if `sync` reports a lock file, the script auto-runs
   `codegraph unlock <path>` and retries once.
4. Verify with `codegraph status <path>` — confirm file / node / edge counts
   match the repo's current size.

## Important caveats

- **Non-zero exit is not always fatal.** `codegraph init` / `sync` may exit
  non-zero when a few files hit the 10s parse timeout (typically the largest
  legacy files), yet the index is still usable. The script warns and continues;
  if symbols look missing, read `.codegraph/errors.log`.
- **Do NOT run `codegraph init` ad hoc during normal investigation.** The
  project convention reserves index bootstrapping for this skill. When an
  explore / query reports a missing index, invoke this skill instead of
  auto-initing.
- The index lives in `.codegraph/` (gitignored); rebuilding is safe. To wipe it
  entirely: `codegraph uninit <path>`.
- The live file-watcher auto-sync runs only while `codegraph serve --mcp` is
  active (with `CODEGRAPH_WATCH_DEBOUNCE_MS=2000`), so after idle periods / pulls
  prefer an explicit `sync` over relying on the watcher.

## Resources

- `scripts/sync_codegraph.sh` — the reusable sync / init script (handles
  missing-index, `--full`, and stale-lock recovery).
- `references/commands.md` — full `codegraph` command reference and edge cases.
