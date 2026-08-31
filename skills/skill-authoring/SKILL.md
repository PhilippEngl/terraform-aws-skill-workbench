---
name: skill-authoring
description: Write or fix a SKILL.md. Use when the user is authoring a skill in the workbench, asks why a skill did not load, or asks what frontmatter is required.
---

# Authoring a skill

A skill is a directory containing `SKILL.md`, optionally alongside `scripts/` and `references/`. The frontmatter is not decoration — a malformed one fails the whole invocation rather than being skipped, so the editor validates it before the file is ever written.

## Required frontmatter

```yaml
---
name: kebab-case-name
description: One sentence on what it does, then when to use it.
---
```

Both keys are required. `name` must be kebab-case and match the directory name. `description` is what the model matches a request against, so write it as *what it does plus when to use it* — a description that only names the topic gives the model nothing to route on.

## Body

Write instructions to the agent, not documentation about the agent. Imperative, specific, and ordered. Prefer a numbered procedure over prose when order matters. State what to report and what to leave out — an agent with no output contract will pad.

Keep it short. Everything here is input tokens on every request in the session.

## What trips people up

Skills are fetched **once per session** and then persist on disk for its duration. Editing a skill does nothing to an open conversation; the workbench's refresh button exists because the only way to load a change is a new `runtimeSessionId`.

Skill content is **trusted input**. The service does not validate, sanitise or inspect it. Treat a skill as code you are executing, because that is what it is.

See `references/frontmatter.md` for the full field list.
