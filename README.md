# team-code-review

Claude Code plugin. Launches a team of 3 parallel code-reviewer agents — **Geddy**, **Alex**, **Neil** (the Rush trio) — each owning an orthogonal review dimension.

| Codename | Dimension |
|---|---|
| **Geddy** | Security & Correctness |
| **Alex** | Standards & Architecture |
| **Neil** | Testability & Performance |

All three read the same full diff of the current branch vs. base; aggregated output is deduplicated and sorted by severity.

## Requirements

- [Claude Code](https://docs.claude.com/en/docs/claude-code)
- `dotnet` CLI (reviewers run `dotnet build` + `dotnet test` as preflight)
- `feature-dev` plugin installed (provides the `code-reviewer` sub-agent used under the hood)
- Optional: `/security-review` skill (sharper security pass), `tokensave` MCP (cross-referencing)

## Install

### Option A — Marketplace (recommended)

From inside Claude Code:

```
/plugin marketplace add lesbass/team-code-review-plugin
/plugin install team-code-review@team-code-review
```

Updates later:

```
/plugin marketplace update team-code-review
```

### Option B — Direct clone

```bash
git clone https://github.com/lesbass/team-code-review-plugin ~/.claude/plugins/team-code-review
```

Then restart Claude Code. The skill `team-code-review` will be discovered automatically.

## Usage

From inside a git repo with the target branch checked out:

```
/team-code-review
```

Optionally paste a PR description / ticket summary as argument so reviewers have plan context to verify implementation against intent.

For Bitbucket PRs: `git fetch && git checkout <pr-branch>` first, then invoke.

## Output

Unified table with columns: `# | Sev | Conf | File:Line | Issue | Fix | By`. Sorted Critical → Important → Low; within severity, Confidence High → Low. Overlapping findings from multiple reviewers are merged into a single row.

## License

MIT — see [LICENSE](LICENSE).
