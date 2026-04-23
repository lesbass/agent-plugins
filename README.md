# team-code-review

Claude Code plugin. Launches a team of 3 parallel code-reviewer agents — **Geddy**, **Alex**, **Neil** (the Rush trio) — each owning an orthogonal review dimension.

| Codename | Dimension |
|---|---|
| **Geddy** | Security & Correctness |
| **Alex** | Standards & Architecture |
| **Neil** | Testability & Performance |

All three read the same full diff of the current branch vs. base; aggregated output is deduplicated and sorted by severity.

## Requirements

- Claude Code
- `dotnet` CLI
- `feature-dev` plugin installed (provides the `code-reviewer` sub-agent used under the hood)
- Optional: `/security-review` skill (sharper security pass), `tokensave` MCP (cross-referencing)

## Install

```bash
claude plugin install https://github.com/<your-org>/team-code-review-plugin
```

Or add as marketplace entry:

```bash
claude plugin marketplace add <your-org>/team-code-review-plugin
```

## Usage

From inside a git repo with the target branch checked out:

```
/team-code-review
```

Optionally paste a PR description / ticket summary as argument to give reviewers plan context.

For Bitbucket PRs: `git fetch && git checkout <pr-branch>` first, then invoke.

## Output

Unified table with columns: `# | Sev | Conf | File:Line | Issue | Fix | By`. Sorted Critical → Important → Low; within severity, Confidence High → Low. Overlapping findings from multiple reviewers are merged.

## License

MIT
