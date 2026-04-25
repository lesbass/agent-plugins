---
name: team-review-and-fix
description: "Use when you want to review the current branch and apply fixes in one shot. Runs team-code-review (Police), presents findings for approval, then runs team-review-fix (Rush) on confirmed findings."
---

# Team Review and Fix

Full pipeline: review → confirm → fix. Orchestrates `team-code-review` and `team-review-fix` in sequence.

```
team-code-review  (Sting, Stewart, Andy — find)
        ↓ findings table
    [user confirms]
        ↓ approved findings
team-review-fix   (Geddy, Alex, Neil — fix)
```

## Execution

### Phase 1 — Review

Execute all steps of `team-code-review` (Steps 0–8) verbatim, including:
- Dependency check
- Base branch detection
- Preflight gate (build + tests)
- Changed-files computation
- Parallel launch of Sting, Stewart, Andy
- Deduplication and unified findings table

**Do NOT proceed to Phase 2 automatically.** After presenting the unified table, stop and ask the user:

```
Review complete. Found {N} findings ({C} Critical, {I} Important, {L} Low).

Before fixing, confirm:
1. Fix all findings? Or exclude specific numbers? (default: fix all)
2. Any findings to mark as won't-fix? (enter numbers, or press Enter to skip)

Proceed with fix? [Y/n]
```

Shut down reviewers (team-code-review Step 9) regardless of whether the user proceeds.

### Phase 2 — Fix (only if user confirms)

If user confirms:
1. Apply any exclusions the user specified (remove those rows from the findings table).
2. Execute all steps of `team-review-fix` (Steps 1–7) with the confirmed findings table as input.

If user declines: report findings table only, stop. Worktrees are not created.

## Notes

- The confirmation gate exists to let the user review findings before any code is changed.
- Partial fixes are fine — excluded findings are not lost, they remain in the review output.
- If the user wants to re-run only the fix phase later, use `team-review-fix` directly with the saved findings table.
