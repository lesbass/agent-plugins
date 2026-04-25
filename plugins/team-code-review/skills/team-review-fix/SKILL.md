---
name: team-review-fix
description: "Use when applying fixes from a team-code-review findings table. Dispatches Rush-named fixer agents (Geddy, Alex, Neil) in parallel git worktrees, one per review dimension."
---

# Team Review Fix

Takes the unified findings table from `team-code-review` and dispatches 3 fixer agents in parallel git worktrees — one per dimension. Named after the Rush *Working Men* lineup.

| Fixer | Dimension | Fixes findings from |
|---|---|---|
| **Geddy** | Security & Correctness | Sting |
| **Alex** | Standards & Architecture | Stewart |
| **Neil** | Testability & Performance | Andy |

## Input

Unified findings table from `team-code-review`, with `By` column containing reviewer codenames (`Sting`, `Stewart`, `Andy`, or combinations like `Sting+Stewart`).

Combined findings (e.g. `Sting+Stewart`) go to both relevant fixers.

## Execution

### Step 1 — Parse and partition findings

Group rows by `By` column:
- Any row mentioning `Sting` → Geddy's queue
- Any row mentioning `Stewart` → Alex's queue
- Any row mentioning `Andy` → Neil's queue

Skip agents whose queue is empty — do not launch them.

### Step 2 — Create worktrees

For each active fixer, create an isolated git worktree:

```bash
git worktree add /tmp/review-fix-geddy  -b review-fix-geddy
git worktree add /tmp/review-fix-alex   -b review-fix-alex
git worktree add /tmp/review-fix-neil   -b review-fix-neil
```

Only run the commands for active fixers.

### Step 3 — Snapshot tmux panes

```bash
tmux list-panes -a -F "#{pane_id}" > /tmp/fix-panes-before.txt 2>/dev/null || true
```

### Step 4 — Launch fixers in parallel

Single message with N Agent calls (N = active fixers):
- `subagent_type`: `general-purpose`
- `run_in_background`: `true`
- `name`: `geddy` | `alex` | `neil`

| Fixer | Prompt file | Findings placeholder |
|---|---|---|
| Geddy | `agents/geddy.md` | `{geddy_findings}` |
| Alex | `agents/alex.md` | `{alex_findings}` |
| Neil | `agents/neil.md` | `{neil_findings}` |

**Placeholders to substitute:**
- `{version}`, `{tech_stack_summary}` — from CLAUDE.md
- `{repo_path}` — absolute repo root
- `{worktree_branch}` — e.g. `review-fix-geddy`
- `{worktree_path}` — e.g. `/tmp/review-fix-geddy`
- `{*_findings}` — the partitioned rows for that agent (plain text, same format as unified table)

### Step 5 — Collect results

As each agent completes, aggregate into a summary:

```
| Fixer  | Branch           | Fixed | Blocked | Commit  |
|--------|------------------|-------|---------|---------|
| Geddy  | review-fix-geddy | 3     | 1       | a1b2c3d |
| Alex   | review-fix-alex  | 2     | 0       | e4f5a6b |
| Neil   | review-fix-neil  | 4     | 2       | c7d8e9f |
```

List BLOCKED findings explicitly with reasons.

### Step 6 — Shutdown and cleanup

```
SendMessage to: geddy  message: {"type": "shutdown_request"}
SendMessage to: alex   message: {"type": "shutdown_request"}
SendMessage to: neil   message: {"type": "shutdown_request"}
```

Kill agent tmux panes:
```bash
if [ -f /tmp/fix-panes-before.txt ]; then
  comm -23 \
    <(tmux list-panes -a -F "#{pane_id}" | sort) \
    <(sort /tmp/fix-panes-before.txt) \
    | xargs -r -I{} tmux kill-pane -t {}
  rm -f /tmp/fix-panes-before.txt
fi
```

Remove worktrees for completed fixers:
```bash
git worktree remove /tmp/review-fix-geddy
git worktree remove /tmp/review-fix-alex
git worktree remove /tmp/review-fix-neil
```

### Step 7 — Report merge strategy

Present the active branches and suggest next steps:
- **No conflicts expected:** `git merge review-fix-geddy review-fix-alex review-fix-neil`
- **Conflicts possible** (same file touched by 2+ fixers): merge one branch at a time, resolve conflicts manually.

## Notes

- Worktrees share the same `.git` — fixers see the same history but write to isolated branches.
- `dotnet build` inside a worktree runs against that worktree's files only.
- Blocked findings are not lost — they appear in the summary for manual follow-up.
- Do not remove worktrees until after the merge is complete.
