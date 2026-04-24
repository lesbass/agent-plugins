# agent-plugins

## Versioning

Before every commit that modifies a plugin, ask the user whether to bump the plugin version in `plugins/<name>/.claude-plugin/plugin.json`. Use semantic versioning:
- patch (1.0.x) — bugfix, doc tweak
- minor (1.x.0) — new feature, refactor, new file
- major (x.0.0) — breaking change

Never bump automatically without asking.
