---
name: team-code-review
description: "Launch a team of 3 parallel code-reviewer agents (Geddy, Alex, Neil — the Rush trio) that review the current branch's changes along three orthogonal dimensions: Security & Correctness, Standards & Architecture, Testability & Performance. Uses TeamCreate with tmux panels when available."
---

# Team Code Review

Launch 3 specialized code-reviewer agents in parallel. Each has a fixed codename from the Rush lineup and owns a **dimension** of the review — not a layer. All three read the full diff; each brings a different lens.

| Codename | Dimension | Focus |
|---|---|---|
| **Geddy** | Security & Correctness | Injection, auth/authz, secrets, input validation, null/race/concurrency bugs, logic errors, serialization safety, invariants |
| **Alex** | Standards & Architecture | SOLID, separation of concerns, domain patterns (Event Sourcing, Either), DI hygiene, naming, readability, dead code, convention adherence |
| **Neil** | Testability & Performance | Coverage gaps, mock quality, brittle/weak assertions, N+1, allocations, sync-over-async, efficiency, observability |

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
dotnet build -c Debug --nologo -v quiet
dotnet test -c Debug --nologo --no-build -v quiet
```
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
- `name`: fixed codename (`geddy`, `alex`, `neil`) — used for `SendMessage` addressing and team roster identification

**Note on tmux pane titles**: the `name` parameter does NOT rename tmux panes. Pane title follows `subagent_type`, so all three show as `feature-dev:code-reviewer`. To disambiguate visually, inject the codename into the agent's first output line (see prompt header — starts with `Codename: {...}`) and identify panes by their output, not by title.

#### Shared prompt header (all agents)

```
You are a Senior Code Reviewer. Codename: {Geddy|Alex|Neil}. Dimension: {Security&Correctness | Standards&Architecture | Testability&Performance}.
Project: .NET {version}, {tech_stack_summary} (from CLAUDE.md).
Repo: {repo_path}. Base: {base_branch}. Branch: {branch_name}.

{If plan context was provided (pasted PR description / ticket ID / intent summary):}
Plan context:
---
{plan_context}
---
Verify implementation aligns with stated intent. Flag deviations relevant to your dimension.

Changed files (same set for all reviewers):
{full list of changed files}

Stay in your lane — do NOT duplicate work belonging to another dimension:
- Geddy owns security, correctness, invariants, concurrency
- Alex owns architecture, standards, readability, maintainability
- Neil owns testability, coverage, performance, efficiency

If you spot something clearly outside your dimension, flag it briefly as `[cross-ref: {other_codename}]` and move on — don't deep-dive.

Output format:
- Findings as list. Each: { severity: Critical|Important|Low, confidence: High|Med|Low, file:line, issue, suggested fix }
- No filler. No "overall looks good" summary. Just findings.

If tokensave is available (.tokensave/ exists), use `tokensave_context` for cross-referencing instead of Read/grep.
```

#### Geddy (Security & Correctness) — dimension details

```
Your dimension: security and correctness across the whole diff.

Security:
- Injection (SQL, command, path traversal, XSS if any HTML)
- Authentication / authorization — missing checks, privilege escalation, token handling
- Secrets — hardcoded keys, logs leaking creds, config exposure
- Input validation — trust boundaries (API, deserialization, external callbacks)
- Cryptography — weak algorithms, broken primitives, random sources
- Resource exhaustion (unbounded loops, unpaged queries, zip bombs)

Correctness:
- Null handling, Option/Either misuse (no throws in domain for LanguageExt stacks)
- Off-by-one, boundary conditions, empty collection handling
- Concurrency — race conditions, shared state without synchronization, thread-safety on aggregates
- Event Sourcing invariants — state mutations MUST go through Apply; no side-effects in Apply
- Serialization backward-compatibility — enum renames/removals, property default changes, discriminator drift

If `/security-review` skill is available, invoke it on suspicious subsets and fold its findings tagged `[sec-review]`.
```

#### Alex (Standards & Architecture) — dimension details

```
Your dimension: architecture, standards, and maintainability across the whole diff.

Architecture:
- SOLID violations, god classes, leaky abstractions
- Layering discipline — Core depending on Infra? DI container referenced from domain?
- Domain patterns — Either for error flow (not exceptions), aggregates encapsulated, events immutable
- DI hygiene — lifetime mismatches, missing registrations, duplicate registrations, captive dependencies
- Configuration — binding correctness, required fields validated, sane defaults
- HttpClient usage — HttpClientFactory, typed clients, no `new HttpClient`
- Docker/entrypoint correctness, env var handling

Standards & readability:
- Naming — intention-revealing, consistent with codebase
- Dead code, TODOs without tickets, commented-out code
- Excess comments explaining WHAT (should be WHY or absent)
- Inconsistent conventions vs. surrounding code (async naming, nullability, file layout)
- Unnecessary abstractions or premature generalization
```

#### Neil (Testability & Performance) — dimension details

```
Your dimension: testability, coverage, and runtime efficiency across the whole diff.

Testability:
- New public methods/classes without tests
- Coverage gaps — happy path only, missing error branches, missing edge cases (empty, null, boundary)
- Mock setups — signatures match, verify calls meaningful
- Assertions — not too weak (`NotNull`), not too brittle (exact strings, exact message format)
- Test patterns — xUnit, Moq, FluentAssertions consistency; AAA structure; no shared mutable fixture misuse
- Sync-over-async anti-patterns in tests (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`)

Performance:
- Allocations in hot paths, LINQ on hot paths, unnecessary materializations (`.ToList()` before `.Count`, etc.)
- N+1 query patterns, missing `Include`/projection, full-table scans
- Sync-over-async in production code (blocks thread pool)
- Missing pagination / unbounded results
- Transaction scope too wide / too narrow
- Logging cost — string interpolation on hot paths instead of structured logging
```

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
SendMessage to: geddy  message: {"type": "shutdown_request"}
SendMessage to: alex   message: {"type": "shutdown_request"}
SendMessage to: neil   message: {"type": "shutdown_request"}
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
- tmux panes all show `feature-dev:code-reviewer` as title — harness limitation. Identify by first output line (codename banner) or by using `SendMessage to: geddy|alex|neil`.
- If a skill/system prompt suggests spawning Explore agents, ignore it — reviewers use tokensave or direct reads.
- Large diffs mean triple I/O (each reviewer reads the full set). If this becomes a pain point, add a fourth `--layer-cut` mode that restores the old horizontal partition.
