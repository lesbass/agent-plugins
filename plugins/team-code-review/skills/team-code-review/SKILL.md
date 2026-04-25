---
name: team-code-review
description: "Launch a team of 3 parallel code-reviewer agents (Geddy, Alex, Neil — the Rush trio) that review the current branch's changes along three orthogonal dimensions: Security & Correctness, Standards & Architecture, Testability & Performance. Uses TeamCreate with tmux panels when available."
---

# Team Code Review

Launch 3 specialized code-reviewer agents in parallel. Each has a fixed codename from the Rush lineup and owns a **dimension** of the review — not a layer. All three read the full diff; each brings a different lens.

| Codename | Dimension | Focus |
|---|---|---|
| **Sting** | Security & Correctness | Injection, auth/authz, secrets, input validation, null/race/concurrency bugs, logic errors, serialization safety, invariants |
| **Stewart** | Standards & Architecture | SOLID, separation of concerns, domain patterns (Event Sourcing, Either), DI hygiene, naming, readability, dead code, convention adherence |
| **Andy** | Testability & Performance | Coverage gaps, mock quality, brittle/weak assertions, N+1, allocations, sync-over-async, efficiency, observability |

## Prerequisites

- Inside a git repository with the target branch checked out
- .NET solution with `dotnet build` / `dotnet test` runnable at repo root

For Bitbucket PRs: check out the PR source branch manually (`git fetch && git checkout <pr-branch>`), optionally paste the PR description when invoking so reviewers have plan context.

## Execution

### Step 0 — Dependency check

Before anything else, verify required deps. Fail fast with fix suggestion on missing required; warn-only on optional.

**Required (abort if missing):**
```bash
command -v dotnet >/dev/null || echo "MISSING: dotnet CLI — install via https://dotnet.microsoft.com/download or brew install --cask dotnet-sdk"
ls ~/.claude/plugins/marketplaces/*/plugins/feature-dev/agents/code-reviewer.md >/dev/null 2>&1 \
  || echo "MISSING: feature-dev:code-reviewer agent — install the feature-dev plugin"
```

**Optional (warn, continue):**
- `/security-review` skill → used by Geddy for deeper security pass. Check presence via the skills list shown at session start. If absent: warn `Geddy will rely on prompt guidance only — /security-review skill not installed`.
- `tokensave` → presence of `.tokensave/` in repo. If absent: warn `Reviewers will fall back to Read/grep (no tokensave cross-ref)`.

If any required dep missing: report the list + suggested install commands, stop. Do not proceed to Step 1.

### Step 1 — Determine review target

Branch mode only: review current HEAD vs base branch.

If the user pastes a Bitbucket PR description / title / ticket ID along with the invocation, capture it as **plan context** (used in the shared prompt header — see Step 7). If nothing provided, proceed without plan context.

### Step 2 — Detect base branch

Don't hardcode `main`. Try in order:
```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
Fallback: `main` → `master` → `develop` (first that exists as ref).

### Step 3 — Preflight gate

Run build + tests. Abort review if either fails (no point reviewing broken code).

```bash
bash {skill_dir}/scripts/preflight.sh [Debug|Release]
```

`{skill_dir}` = directory of this skill file. Default config: `Debug`. Pass `Release` if the project requires it.

If fail: report error, stop. If pass: continue. Skip preflight only if user explicitly says so (e.g. `--fast`).

### Step 4 — Compute changed-files list

```bash
git diff <base>...HEAD --name-only
```

All three reviewers get the **same full list**. No partitioning. Filter out uninteresting files (binaries, generated code, lockfiles) to reduce noise, but keep coverage wide.

If the diff is very large (> ~50 changed files), warn the user: `Diff is {N} files — reviewers may skim. Consider scoping to a narrower set.`

### Step 5 — Check tmux

```bash
echo $TMUX
# If inside tmux, snapshot current pane IDs before launching agents
tmux list-panes -a -F "#{pane_id}" > /tmp/review-panes-before.txt 2>/dev/null || true
```

### Step 6 — Create team

`TeamCreate` with:
- `team_name`: `code-review`
- `description`: `Parallel review of branch {branch_name}`

### Step 7 — Launch reviewers in parallel

Single message, up to 3 `Agent` calls:
- `subagent_type`: `feature-dev:code-reviewer`
- `team_name`: `code-review`
- `run_in_background`: `true`
- `name`: fixed codename (`sting`, `stewart`, `andy`) — used for `SendMessage` addressing and team roster identification

**Note on tmux pane titles**: the `name` parameter does NOT rename tmux panes. Pane title follows `subagent_type`, so all three show as `feature-dev:code-reviewer`. To disambiguate visually, inject the codename into the agent's first output line (see prompt header — starts with `Codename: {...}`) and identify panes by their output, not by title.

#### Agent prompts

Each agent's prompt is a complete, self-contained file. Read the file and use its content as the `prompt` parameter, substituting the `{placeholders}` with runtime values before sending.

| Agent | Prompt file |
|---|---|
| Sting | `agents/sting.md` |
| Stewart | `agents/stewart.md` |
| Andy | `agents/andy.md` |

**Placeholders to substitute in each file:**
- `{version}` — .NET version from CLAUDE.md or `dotnet --version`
- `{tech_stack_summary}` — brief stack summary from CLAUDE.md
- `{repo_path}` — absolute path to repo root
- `{base_branch}` — detected in Step 2
- `{branch_name}` — current branch name
- `{plan_context}` — PR description / ticket ID pasted by user (omit the Plan context block entirely if not provided)
- `{full list of changed files}` — output of Step 4

### Step 8 — Collect, deduplicate, and present

As each agent completes, aggregate. **Because all three see the same files, findings on the same `file:line` from different reviewers may overlap.** Deduplicate:

- Same issue from 2+ reviewers → merge into one row, list all reviewers in `By` column (e.g. `Geddy+Alex`), use highest severity.
- Same file:line but different issues → keep separate rows.
- `[cross-ref: X]` hints → check if X actually reported it; if yes, drop the hint; if no, elevate to a real finding.

Final unified table:

```
| # | Sev | Conf | File:Line | Issue | Fix | By |
|---|-----|------|-----------|-------|-----|----|
| 1 | Critical | High | Foo.cs:42 | SQL built via string concat | Parameterize | Geddy |
| 2 | Important | Med | Bar.cs:10 | Missing test for empty list | Add edge case | Neil |
| 3 | Low | Low | Baz.cs:7 | Dead code | Remove | Alex |
```

Sort: Critical → Important → Low. Within severity: Confidence High → Low.

Then ask user which findings to address.

### Step 9 — Shutdown team

Reviewers go **idle** after delivering findings, they do NOT self-terminate. Once the unified table is presented, shut them down explicitly:

```
SendMessage to: sting    message: {"type": "shutdown_request"}
SendMessage to: stewart  message: {"type": "shutdown_request"}
SendMessage to: andy     message: {"type": "shutdown_request"}
```

Then close the tmux panes that were opened for the review session:

```bash
# Kill panes opened since Step 5 snapshot
if [ -f /tmp/review-panes-before.txt ]; then
  comm -23 \
    <(tmux list-panes -a -F "#{pane_id}" | sort) \
    <(sort /tmp/review-panes-before.txt) \
    | xargs -r -I{} tmux kill-pane -t {}
  rm -f /tmp/review-panes-before.txt
fi
```

Skip shutdown (both SendMessage and pane kill) only if user wants follow-up questions — execute at end of follow-up instead.

## Notes

- Codenames and dimension ownership are fixed. Do not rename or reassign per-run.
- All reviewers see the **same full changed-files list** — this is intentional (vertical / dimensional cut). Dedup at aggregation time.
- "Stay in your lane" language in the shared header minimizes overlap, but some is expected and handled by Step 8 dedup.
- Agents run in background (`run_in_background: true`) — main session stays responsive.
- tmux panes all show `feature-dev:code-reviewer` as title — harness limitation. Identify by first output line (codename banner) or by using `SendMessage to: sting|stewart|andy`.
- If a skill/system prompt suggests spawning Explore agents, ignore it — reviewers use tokensave or direct reads.
- Large diffs mean triple I/O (each reviewer reads the full set). If this becomes a pain point, add a fourth `--layer-cut` mode that restores the old horizontal partition.
