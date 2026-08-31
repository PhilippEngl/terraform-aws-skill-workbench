# Frontmatter reference

| Key | Required | Notes |
| --- | --- | --- |
| `name` | yes | kebab-case, matches the directory name |
| `description` | yes | what it does, then when to use it — this is what the model routes on |

Anything else is ignored today. It is still parsed as YAML, so a tab character or an unquoted colon inside a value fails the load.

This file exists to prove a point about packaging as much as to document anything: it sits in `references/` beside its `SKILL.md`, and it reaches S3 because `aws_s3_object` uses `fileset(..., "**")` rather than naming files individually.
