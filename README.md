# agent-plugins

A Claude Code **marketplace** hosting plugins I build for my own workflow. Install the marketplace once, then pick and choose individual plugins.

## Plugins in this marketplace

| Plugin | Purpose |
|---|---|
| [`team-code-review`](plugins/team-code-review) | Rush-themed 3-agent parallel code reviewer (Geddy / Alex / Neil) covering Security & Correctness, Standards & Architecture, Testability & Performance. .NET-oriented. |

More will land here over time.

## Install the marketplace

From inside Claude Code:

```
/plugin marketplace add lesbass/agent-plugins
```

Then install any plugin by name:

```
/plugin install team-code-review@agent-plugins
```

Update later:

```
/plugin marketplace update agent-plugins
```

## One-liner to share with teammates

Paste both commands together into Claude Code — they'll run in sequence:

```
/plugin marketplace add lesbass/agent-plugins
/plugin install team-code-review@agent-plugins
```

## Plugin-specific docs

Each plugin has its own README / SKILL.md under `plugins/<name>/`. See:

- [`plugins/team-code-review/skills/team-code-review/SKILL.md`](plugins/team-code-review/skills/team-code-review/SKILL.md) — full spec of the review flow, prompts, and aggregation logic.

## License

MIT — see [LICENSE](LICENSE). Applies to all plugins in this repository unless overridden.
