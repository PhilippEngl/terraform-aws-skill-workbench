---
name: terraform-review
description: Review a Terraform change against this repository's conventions. Use when the user pastes HCL, asks whether a resource is named correctly, or asks what is wrong with a plan.
---

# Reviewing Terraform in this repository

Check these in order and report only what is actually wrong. Do not restate what is already correct.

## Naming

Resource names are lowercase with dashes, `<prefix>-<component>-<role>`, for example `demo-skill-workbench-lambda-sg`. The component segment is not optional — two deployments in one account otherwise collide on generic roles like `sg`. Per-AZ resources append the AZ name.

Code identifiers are `snake_case`: resource labels, variables, locals, outputs.

AgentCore harness and endpoint names match `^[a-zA-Z][a-zA-Z0-9_]{0,39}$` and reject dashes. They must be derived with `replace(..., "-", "_")` and asserted at plan time with a `validation` block, not checked by hand.

## Tagging

`Project`, `Environment` and `ManagedBy` come from `default_tags` in the provider. A resource repeating any of them is wrong. Resource-level `tags` carry only `Name` and role-specific keys.

## Things that are silently broken

- A Lambda without an explicit `aws_cloudwatch_log_group`. Lambda auto-creates one, Terraform never owns it, and every destroy leaves it behind.
- `etag` on an `aws_s3_object` in an SSE-KMS bucket. The ETag is not the plaintext MD5, so this shows a permanent diff. Use `source_hash`.
- An AgentCore resource without `depends_on` covering its role's policies. Terraform's implicit dependency reaches `role_arn` but not the `aws_iam_role_policy` resources, so the service's create-time permission pre-flight can read an empty role.
- A missing `default` on a variable. Every variable in this repository is defaulted; `terraform apply` with no `-var` flags is the expected path.

## Reporting

Quote the offending line, say what is wrong in one sentence, and give the corrected line. If nothing is wrong, say so in one sentence and stop.
