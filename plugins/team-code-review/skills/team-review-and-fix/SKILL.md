---
name: team-review-and-fix
description: "Use when you want to review the current branch and apply fixes in one shot. Runs team-code-review (Police), presents findings for approval, then runs team-review-fix (Rush) on confirmed findings."
---

# Team Review and Fix

Full pipeline: review → confirm → fix. Orchestrates `team-code-review` and `team-review-fix` in sequence.

```
team-code-review  (Sting, Stewart, Andy — find)
        ↓ findings table → written to .reviews/{code}-review-{date}.md
    [user confirms]
        ↓ approved findings
team-review-fix   (Geddy, Alex, Neil — fix)
        ↓ fix report → written to .reviews/{code}-fix-{date}.md
```

## Step 0 — Derive session code

Extract a short code from the current branch name to use as file prefix:

```bash
branch=$(git rev-parse --abbrev-ref HEAD)
# Strip common prefixes: feature/, fix/, hotfix/, bugfix/, chore/, release/
code=$(echo "$branch" | sed 's|^feature/||; s|^fix/||; s|^hotfix/||; s|^bugfix/||; s|^chore/||; s|^release/||')
date=$(date +%Y-%m-%d)
review_file=".reviews/${code}-review-${date}.md"
fix_file=".reviews/${code}-fix-${date}.md"
mkdir -p .reviews
```

Examples:
- `feature/PROJ-123-add-auth` → `PROJ-123-add-auth-review-2026-04-25.md`
- `fix/workstep-null-check` → `workstep-null-check-review-2026-04-25.md`
- `workstep-service` → `workstep-service-review-2026-04-25.md`

## Phase 1 — Review

Execute all steps of `team-code-review` (Steps 0–8) verbatim, including:
- Dependency check
- Base branch detection
- Preflight gate (build + tests)
- Changed-files computation
- Parallel launch of Sting, Stewart, Andy
- Deduplication and unified findings table

After building the unified findings table, **write it to `{review_file}`** with this structure:

```markdown
# Code Review — {branch_name}

**Date:** {date}  
**Base branch:** {base_branch}  
**Reviewers:** Sting (Security & Correctness), Stewart (Standards & Architecture), Andy (Testability & Performance)

## Findings

| # | Sev | Conf | File:Line | Issue | Fix | By |
|---|-----|------|-----------|-------|-----|----|
...

## Closing song

🎵 *"{lyric}"* — **{song}**, The Police  
{youtube_url}
```

**Do NOT proceed to Phase 2 automatically.** After presenting the unified table and confirming the file was written, stop and ask the user:

```
Review complete. Found {N} findings ({C} Critical, {I} Important, {L} Low).
Written to {review_file}.

Before fixing, confirm:
1. Fix all findings? Or exclude specific numbers? (default: fix all)
2. Any findings to mark as won't-fix? (enter numbers, or press Enter to skip)

Proceed with fix? [Y/n]
```

Shut down reviewers (team-code-review Step 9) regardless of whether the user proceeds.

## Phase 2 — Fix (only if user confirms)

If user confirms:
1. Apply any exclusions the user specified (remove those rows from the findings table).
2. Execute all steps of `team-review-fix` (Steps 1–7) with the confirmed findings table as input.

After collecting the fix results (team-review-fix Step 5), **write the fix report to `{fix_file}`** with this structure:

```markdown
# Fix Report — {branch_name}

**Date:** {date}  
**Fixers:** Geddy (Security & Correctness), Alex (Standards & Architecture), Neil (Testability & Performance)  
**Review file:** {review_file}

## Results

| Fixer | Branch | Fixed | Blocked | Commit |
|-------|--------|-------|---------|--------|
...

## Blocked findings

{list each blocked finding with reason, or "None" if all fixed}

## Merge strategy

{no-conflict or per-branch merge instructions}

## Closing song

🎵 *"{lyric}"* — **{song}**, Rush  
{youtube_url}
```

If user declines fix: write only the review file (already done in Phase 1), stop. Worktrees are not created.

## Notes

- `.reviews/` directory is created automatically if missing. Add to `.gitignore` or track it — your choice.
- If the same branch is reviewed multiple times on the same day, the file is overwritten. Add a counter suffix manually if needed.
- Excluded findings still appear in the review file — they are not removed, just not passed to the fixers.
- If the user wants to re-run only the fix phase later, use `lesbass-skills:team-review-fix` directly and point to the saved review file for context.
