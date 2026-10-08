# codegraph — command reference & edge cases

Installed CLI: `codegraph` (Windows launcher `codegraph.cmd` at
`%LOCALAPPDATA%\codegraph\current\bin`). Works on any platform once installed.

## Discovery

```
codegraph --help
```

## Commands used by the sync skill

| Command | Purpose | Notes |
| --- | --- | --- |
| `codegraph init [--yes] [path]` | Build the initial index in `path` (default CWD). Creates `.codegraph/`. | `--yes` skips every prompt (for scripts / CI). Indexing runs by default. May exit non-zero on per-file parse timeouts but still produce a usable index. |
| `codegraph sync [-q] [path]` | Incremental sync of changes since last index. | `-q` suppresses output (for git hooks). Use this after git pulls / branch switches. |
| `codegraph index [path]` | Full rebuild from scratch (same result as fresh `init`). | Slower; use when `sync` looks stale or after many structural changes. |
| `codegraph status [path]` | Index stats: files, nodes, edges, DB size, backend. | Verify after sync. |
| `codegraph unlock [path]` | Remove a stale lock file blocking indexing. | Run when sync/init reports a lock. |
| `codegraph uninit [path]` | Delete `.codegraph/` entirely. | Wipes the index; safe to rebuild. |

## Query commands (read-only; require an existing index)

- `codegraph explore "<query>"` — symbols' source + call paths in one shot (same
  as the `codegraph_explore` MCP tool).
- `codegraph query "<search>"` — symbol search.
- `codegraph node [name]` — one symbol's source + caller/callee trail.
- `codegraph callers <symbol>` / `codegraph callees <symbol>` / `codegraph impact <symbol>`.
- `codegraph files` — project file structure from the index.

## Edge cases / gotchas

- **No auto-init.** `explore`/`query` on a dir without `.codegraph/` reports
  *"no .codegraph/ index exists ... run 'codegraph init'"* and tells the agent
  NOT to auto-run init. Invoke the `codegraph-sync` skill instead.
- **Parse timeouts are non-fatal.** Large legacy files (> ~900 lines) can exceed
  the 10s worker timeout; the index is still usable but those files are absent
  from the graph. Check `.codegraph/errors.log`.
- **Watcher only while served.** `codegraph serve --mcp` runs a file watcher
  (debounce `CODEGRAPH_WATCH_DEBOUNCE_MS=2000`). After idle / pull, prefer an
  explicit `sync`.
- **Config via `codegraph.json`.** Lives at repo root (commit it so clones carry
  the exclude/deprioritize config). `.codegraph/` is gitignored and rebuilt per
  machine.
