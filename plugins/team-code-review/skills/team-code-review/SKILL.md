---
name: team-code-review
description: "Launch a team of 3 parallel code-reviewer agents (Sting, Stewart, Andy — The Police trio) that review the current branch's changes along three orthogonal dimensions: Security & Correctness, Standards & Architecture, Testability & Performance. Uses TeamCreate with tmux panels when available."
---

# Team Code Review

Launch 3 specialized code-reviewer agents in parallel. Each has a fixed codename from The Police lineup and owns a **dimension** of the review — not a layer. All three read the full diff; each brings a different lens.

| Codename | Dimension | Focus |
|---|---|---|
| **Sting** | Security & Correctness | Injection, auth/authz, secrets, input validation, null/race/concurrency bugs, logic errors, serialization safety, invariants |
| **Stewart** | Standards & Architecture | SOLID, separation of concerns, domain patterns (Event Sourcing, Either), DI hygiene, naming, readability, dead code, convention adherence |
| **Andy** | Testability & Performance | Coverage gaps, mock quality, brittle/weak assertions, N+1, allocations, sync-over-async, efficiency, observability |

## Prerequisites

- Inside a git repository with the target branch checked out
- Build and tests runnable from repo root (either .NET or TypeScript/Node project)

For Bitbucket PRs: check out the PR source branch manually (`git fetch && git checkout <pr-branch>`), optionally paste the PR description when invoking so reviewers have plan context.

## Execution

### Step 0 — Detect stack + dependency check

**Detect stack** (run from repo root):
```bash
if ls *.sln *.csproj 2>/dev/null | grep -q .; then
  echo "STACK=dotnet"
elif [ -f package.json ]; then
  echo "STACK=node"
else
  echo "STACK=unknown"
fi
```

Set `{stack}` to `dotnet` or `node` (or `unknown`). Use it to drive all subsequent stack-specific steps.

**Required deps (abort if missing):**

For `STACK=dotnet`:
```bash
command -v dotnet >/dev/null || echo "MISSING: dotnet CLI — install via https://dotnet.microsoft.com/download or brew install --cask dotnet-sdk"
```

For `STACK=node`:
```bash
command -v node >/dev/null || echo "MISSING: node — install via https://nodejs.org or nvm"
# detect package manager: prefer yarn if yarn.lock exists, pnpm if pnpm-lock.yaml, else npm
[ -f yarn.lock ] && echo "PKG=yarn" || ([ -f pnpm-lock.yaml ] && echo "PKG=pnpm" || echo "PKG=npm")
```

Always required:
```bash
ls ~/.claude/plugins/marketplaces/*/plugins/feature-dev/agents/code-reviewer.md >/dev/null 2>&1 \
  || echo "MISSING: feature-dev:code-reviewer agent — install the feature-dev plugin"
```

**Optional (warn, continue):**
- `/security-review` skill → used by Sting for deeper security pass. Check presence via the skills list shown at session start. If absent: warn `Sting will rely on prompt guidance only — /security-review skill not installed`.
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

Run build only (no tests — too slow at review start). Abort review if build fails.

```bash
bash {skill_dir}/scripts/preflight.sh {stack} [Debug|Release]
```

`{skill_dir}` = directory of this skill file. `{stack}` = `dotnet` or `node` (from Step 0). Default config for .NET: `Debug`. Pass `Release` if the project requires it.

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
- `{tech_stack_summary}` — brief stack summary from CLAUDE.md; if absent, derive from Step 0 detection (e.g. `TypeScript/React, Node 20` or `.NET 8, ASP.NET Core`)
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
| 1 | Critical | High | Foo.cs:42 | SQL built via string concat | Parameterize | Sting |
| 2 | Important | Med | Bar.cs:10 | Missing test for empty list | Add edge case | Andy |
| 3 | Low | Low | Baz.cs:7 | Dead code | Remove | Stewart |
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

### Step 10 — Closing song

After shutdown, pick one Police song from the list below that best fits the review outcome. Present: song title, the chosen lyric, and the YouTube search link.

| Outcome | Song | Lyric |
|---|---|---|
| Clean — zero or only Low findings | "Walking on the Moon" | *"Giant steps are what you take / walking on the moon"* |
| Few findings, all manageable | "Message in a Bottle" | *"I'll send an SOS to the world"* |
| Several Important findings | "Don't Stand So Close to Me" | *"This girl is half his age"* — the code is exposing things it shouldn't |
| Critical security findings | "Roxanne" | *"You don't have to put on the red light"* — stop shipping unsafe code |
| Widespread correctness issues | "Synchronicity II" | *"Many miles away, something crawls from the slime"* |
| Architecture/design chaos | "Demolition Man" | *"I'm a walking nightmare, an arsenal of doom"* |
| Everything on fire — many Critical | "Every Breath You Take" | *"Every move you make, I'll be watching you"* — someone needs to watch this code |
| Mixed bag, some good some bad | "De Do Do Do, De Da Da Da" | *"Their logic ties me up and robs me blind"* |

YouTube search base URL: `https://www.youtube.com/results?search_query=The+Police+{Song+Title+URL+encoded}`

Example: for "Roxanne" → `https://www.youtube.com/results?search_query=The+Police+Roxanne+Official`

## Notes

- Codenames and dimension ownership are fixed. Do not rename or reassign per-run.
- All reviewers see the **same full changed-files list** — this is intentional (vertical / dimensional cut). Dedup at aggregation time.
- "Stay in your lane" language in the shared header minimizes overlap, but some is expected and handled by Step 8 dedup.
- Agents run in background (`run_in_background: true`) — main session stays responsive.
- tmux panes all show `feature-dev:code-reviewer` as title — harness limitation. Identify by first output line (codename banner) or by using `SendMessage to: sting|stewart|andy`.
- If a skill/system prompt suggests spawning Explore agents, ignore it — reviewers use tokensave or direct reads.
- Large diffs mean triple I/O (each reviewer reads the full set). If this becomes a pain point, add a fourth `--layer-cut` mode that restores the old horizontal partition.
