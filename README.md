# terraform-aws-skill-workbench

A Terraform module that deploys a browser-based workbench for authoring and testing [Agent Skills](https://docs.aws.amazon.com/bedrock-agentcore/) against an Amazon Bedrock AgentCore harness running in your VPC.

You write a `SKILL.md` in the browser, save it, and immediately ask the agent to use it. The agent loads your skills plus a set of curated ones on every invocation, so the loop from editing a skill to seeing its effect is one refresh.

## What it creates

- An **AgentCore harness** in VPC mode, with managed long-term memory, the built-in file operations tool and the managed browser tool. `shell` is deliberately excluded — see [ADR 3](docs/adr/0003-shell-is-excluded.md).
- A **proxy Lambda** that is the security boundary. The browser can invoke this function and nothing else; every skill read, write and agent invocation goes through it. See [ADR 1](docs/adr/0001-two-prefixes-and-a-constructing-proxy.md).
- An **S3 bucket with two prefixes**: `users/<identity>/` for skills a person authors, `shared/` for skills Terraform manages. A user can never read `shared/` directly, only observe its effect on the agent.
- A **KMS key** encrypting both the bucket and the harness's memory.
- **Cognito** user pool, client, identity pool, and an authenticated role holding exactly one permission.
- An **Amplify app** to serve the React frontend.
- Two **security groups**, and optionally the **VPC endpoints** the harness needs.

It does **not** create a VPC, subnets, NAT gateways or route tables. Those stay with whoever owns the account.

## Requirements

Terraform >= 1.9, the AWS provider >= 6.61, and a region where AgentCore is available.

**Python 3.6 or newer must be installed on whatever machine runs Terraform.** The proxy Lambda is packaged by [`terraform-aws-modules/lambda/aws`](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest), which builds the deployment package with a Python script driven by an `external` data source. That also brings the `external`, `local` and `null` providers into your dependency lock file transitively. If you run Terraform on a hosted runner without Python, you need a worker image that has it.

Four things the module cannot check for you:

1. **Interface VPC endpoints for `ecr.api`, `ecr.dkr` and `logs`.** VPC mode is egress-only, and the harness pulls its managed container image from a private ECR repository in an AWS-owned account. Without these, sessions fail on an image pull timeout that names neither the endpoint nor the network. The module can create them — see [Networking](#networking).
2. **A route to S3.** Skills are fetched from S3 at session start. A gateway endpoint or an interface endpoint, either is fine.
3. **Private subnets with a NAT route.** Not a recommendation. A harness ENI is assigned no public IP, so a public subnet leaves it with no egress path at all.
4. **A model that exists in your region.** `agent_model_id` is required and has no default, because no single model ID is available everywhere. A geo prefix such as `us.` or `eu.` selects a cross-region inference profile and determines which regions inference may run in.

## Usage

```hcl
module "skill_workbench" {
  source = "github.com/your-org/terraform-aws-skill-workbench?ref=v0.1.0"

  name_prefix = "demo"

  vpc_id             = "vpc-0123456789abcdef0"
  private_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  agent_model_id = "us.anthropic.claude-sonnet-4-6"
}
```

Two worked examples: [`examples/complete`](examples/complete) for a VPC that already has the endpoints, and [`examples/greenfield`](examples/greenfield) for one that does not. Both are templates with placeholder identifiers.

### `terraform apply` is not the whole install

**Apply alone leaves a site that serves nothing.** No repository is connected to the Amplify app, so Amplify never builds anything itself and `amplify_app_url` returns a URL that 404s. Two steps finish the job:

```sh
make user       # create a Cognito user, interactively
make frontend   # build the React app and upload it to Amplify
```

Both read Terraform outputs from `TF_DIR`, which defaults to `examples/complete`. Point it at your own root configuration:

```sh
make frontend TF_DIR=../my-infra
```

The frontend is built by Vite, which bakes the Cognito and model configuration into the bundle at build time. That is why `make frontend` needs the infrastructure applied at least once, and why changing `agent_model_id` means rebuilding the frontend as well as re-applying.

### Then verify the tool surface

The first thing to do after an apply is ask the agent what tools it can call, and compare the answer with `allowed_tools`. A name in `allowed_tools` that matches nothing leaves the model with **no tools and no error** — it answers normally and fabricates results.

`file_operations` has been observed working. `browser` is attached but has not been observed being used; treat the claim as unverified until you see it browse.

## Working on the module

Every one of these runs with **no AWS credentials and nothing deployed**, which is the fast loop:

```sh
make fmt-check           # canonical formatting
make validate            # the module itself
make validate-modules    # the nested modules
make validate-examples   # both examples
make test                # the proxy Lambda's unit tests
make test-tf             # plan-only Terraform assertions, provider mocked
make frontend-check      # type-check and production build
make frontend-serve      # serve the UI on localhost:5173, layout only
make check-public        # scan for content that should not be published
make lint                # tflint, if installed
make docs                # regenerate the tables below
```

## Security scanning

[ASH](https://github.com/awslabs/automated-security-helper) orchestrates several scanners in one pass, which is what suits a repository that is not one language: Checkov reads the Terraform, Bandit the proxy Lambda, npm-audit the frontend's lock file, detect-secrets everything.

```sh
make scan                # local mode
make scan-container      # adds the scanners local mode cannot install
make scan-report         # summarise the last scan without re-scanning
```

`make scan` is the one gate that needs no AWS credentials but does need the network: ASH is fetched with `uvx`, pinned to `ASH_VERSION`, and each scanner lands in its own isolated environment on first run. The only prerequisite is [uv](https://docs.astral.sh/uv/getting-started/installation/). Nothing is installed into the repository.

**A finding fails the target.** ASH exits 2 when anything reaches `ASH_MIN_SEVERITY`, which defaults to `medium` — this is a gate, not a report. Loosen it per invocation rather than in the file:

```sh
make scan ASH_MIN_SEVERITY=critical
make scan-container ASH_OCI_RUNNER=finch    # any OCI runtime works
```

Local mode runs only what uv can install. cfn-nag needs Ruby, and Grype and Syft are separate binaries, so those three report `MISSING` until you install them or use `make scan-container`, which costs an image build the first time.

What is in scope is narrowed by [`.ash/.ash.yaml`](.ash/.ash.yaml), and the reason is worth knowing: ASH does not honour `.gitignore` for `.terraform/`, so without that file most findings come from the vendored source of `terraform-aws-modules/lambda/aws`, once per example that has been initialised. Nothing in it disables a scanner. Output lands in the gitignored `.ash/ash_output/`, and `make clean` removes it.

Everything else above runs offline. The targets that touch AWS act on a **root configuration**, not on the module — a module is never applied directly. `TF_DIR` selects which one and defaults to `examples/complete`:

```sh
make plan                        # terraform plan in TF_DIR
make apply                       # interactive; creates billable resources
make output
make destroy                     # ordered teardown, see below
make plan TF_DIR=../my-infra     # against your own root configuration
```

`make user`, `make frontend` and `make frontend-env` read `TF_DIR`'s outputs the same way.

## Reference

Generated by `terraform-docs`. Run `make docs` after changing a variable or output.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.61, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.61, < 7.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_auth"></a> [auth](#module\_auth) | ./modules/cognito-user-pool | n/a |
| <a name="module_harness"></a> [harness](#module\_harness) | ./modules/agentcore-harness | n/a |
| <a name="module_proxy_lambda"></a> [proxy\_lambda](#module\_proxy\_lambda) | terraform-aws-modules/lambda/aws | 8.8.0 |
| <a name="module_skill_bucket"></a> [skill\_bucket](#module\_skill\_bucket) | ./modules/s3-bucket | n/a |
| <a name="module_skills_key"></a> [skills\_key](#module\_skills\_key) | ./modules/kms-key | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_amplify_app.frontend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/amplify_app) | resource |
| [aws_amplify_branch.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/amplify_branch) | resource |
| [aws_iam_role.amplify](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_s3_object.shared_skill](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.endpoints](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.harness](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint_route_table_association.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint_route_table_association) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.amplify_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.authenticated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.harness_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.proxy_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_agent_model_id"></a> [agent\_model\_id](#input\_agent\_model\_id) | Bedrock model or inference profile ID the harness is configured with. Required, because no single model ID is available in every region: a geo prefix such as us. or eu. selects a cross-region inference profile and must match the geography of the region you are deploying into. | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnets with a NAT route. Public subnets do not work: no public IP is assigned to a harness ENI, so there is no egress path and sessions fail on image pull. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the harness ENIs and the proxy Lambda are placed in | `string` | n/a | yes |
| <a name="input_access_log_bucket_name"></a> [access\_log\_bucket\_name](#input\_access\_log\_bucket\_name) | Existing bucket to deliver the skill bucket's S3 server access logs to. Null, the default, disables access logging: the module does not create a log destination. Supply one when you want to detect access that did not come through the proxy — in-band requests are already logged by the proxy Lambda, which is the only S3 caller. The bucket must be in this region and account, must not use SSE-KMS, and its policy must already allow s3:PutObject for logging.s3.amazonaws.com with your account as aws:SourceAccount. All three are AWS constraints on log delivery, and breaking any of them fails by silently never delivering a log. | `string` | `null` | no |
| <a name="input_additional_agent_model_ids"></a> [additional\_agent\_model\_ids](#input\_additional\_agent\_model\_ids) | Further models a caller may name per invocation. The frontend offers a model picker, and a per-invocation model replaces the configured one rather than supplementing it, so any model offered in the picker needs permission here or overriding requests fail with AccessDenied while the default model succeeds. | `list(string)` | `[]` | no |
| <a name="input_agent_max_tokens"></a> [agent\_max\_tokens](#input\_agent\_max\_tokens) | Output token budget for one whole invocation, enforced by the harness. Null leaves it unlimited. A cost control in the same family as max\_iterations and timeout\_seconds. | `number` | `null` | no |
| <a name="input_agent_model_max_tokens"></a> [agent\_model\_max\_tokens](#input\_agent\_model\_max\_tokens) | Max tokens passed to the model for a single request. Null uses the model's default. Distinct from agent\_max\_tokens, which bounds the whole invocation. | `number` | `null` | no |
| <a name="input_agent_model_temperature"></a> [agent\_model\_temperature](#input\_agent\_model\_temperature) | Sampling temperature passed to the model. Set 0 for the most repeatable output, which is what you want when comparing two runs of the same skill. Null uses the model's default. | `number` | `null` | no |
| <a name="input_agent_model_top_p"></a> [agent\_model\_top\_p](#input\_agent\_model\_top\_p) | Nucleus sampling parameter passed to the model. Setting this and temperature together is usually a mistake; pick one. Null uses the model's default. | `number` | `null` | no |
| <a name="input_allowed_tools"></a> [allowed\_tools](#input\_allowed\_tools) | Tool patterns the harness may select. shell is deliberately excluded: the workbench exists to exercise Skills, and a skill that can shell out can read the shared prefix and exfiltrate it. Set to null to allow every tool. A name that matches nothing leaves the model with no tools and no error, so verify against a deployed harness before changing it. | `list(string)` | <pre>[<br/>  "@builtin/file_operations",<br/>  "browser"<br/>]</pre> | no |
| <a name="input_create_s3_gateway_endpoint"></a> [create\_s3\_gateway\_endpoint](#input\_create\_s3\_gateway\_endpoint) | Whether to create the S3 gateway endpoint. Skills are fetched from S3 by both the harness and the proxy, so a route to S3 is required — but a gateway endpoint is VPC-wide and route-table-scoped, so creating one in a shared VPC affects workloads this module knows nothing about. | `bool` | `false` | no |
| <a name="input_enable_browser_tool"></a> [enable\_browser\_tool](#input\_enable\_browser\_tool) | Whether to attach the managed AgentCore browser tool. It is the one tool a skill can usefully drive without shell access. | `bool` | `true` | no |
| <a name="input_frontend_dev_origins"></a> [frontend\_dev\_origins](#input\_frontend\_dev\_origins) | Extra CORS origins allowed to read the skill bucket. Without the Vite dev server here, reading a skill from a locally served frontend fails on CORS. | `list(string)` | <pre>[<br/>  "http://localhost:5173"<br/>]</pre> | no |
| <a name="input_log_level"></a> [log\_level](#input\_log\_level) | Log level for the proxy Lambda, read by the Powertools logger as POWERTOOLS\_LOG\_LEVEL. Set to DEBUG when diagnosing an invocation; the handler logs the full incoming event at INFO regardless, which includes the developer's prompt and any SKILL.md body they saved. | `string` | `"INFO"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the proxy Lambda's CloudWatch Logs group. Exposed because an organisation with a retention policy has to be able to set it, and because a log group with no retention keeps everything forever and bills for it forever. The module always owns the log group rather than letting Lambda auto-create one, so this is honoured and a destroy leaves nothing behind. | `number` | `14` | no |
| <a name="input_max_iterations"></a> [max\_iterations](#input\_max\_iterations) | Reasoning and action cycles per invocation. The service default is 75. | `number` | `15` | no |
| <a name="input_memory_event_expiry_days"></a> [memory\_event\_expiry\_days](#input\_memory\_event\_expiry\_days) | How long conversation events are retained, in days. A count of days, not an ISO-8601 duration. | `number` | `30` | no |
| <a name="input_memory_strategies"></a> [memory\_strategies](#input\_memory\_strategies) | Long-term memory strategies for the managed memory the harness creates. Memory is scoped by actorId rather than by session, so a conversation survives the session rotation the frontend performs to reload skills. | `list(string)` | <pre>[<br/>  "SEMANTIC",<br/>  "SUMMARIZATION",<br/>  "USER_PREFERENCE"<br/>]</pre> | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every resource name this module creates. Names are derived as <name\_prefix>-skill-workbench-<role>. | `string` | `"demo"` | no |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | Route tables the S3 gateway endpoint is associated with. Required when create\_s3\_gateway\_endpoint is true, ignored otherwise. A gateway endpoint with no association routes nothing. | `list(string)` | `[]` | no |
| <a name="input_system_prompt"></a> [system\_prompt](#input\_system\_prompt) | System prompt for the workbench agent. Deliberately thin: the point of the module is that behaviour comes from Skills, not from this. | `string` | `"You are a skill-testing assistant running inside a developer workbench.\n\nYour behaviour is defined almost entirely by the Skills loaded into this session,\nnot by this prompt. Read the skills available to you before answering, follow\nwhichever one matches the request, and say plainly when none of them applies\nrather than improvising.\n\nWhen asked what you can do, list the skills you actually loaded and the tools you\ncan actually call. Do not describe capabilities you cannot verify.\n"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource. Merged with a Name tag the module sets itself, which takes precedence. | `map(string)` | `{}` | no |
| <a name="input_timeout_seconds"></a> [timeout\_seconds](#input\_timeout\_seconds) | Wall-clock timeout for one harness invocation. The proxy Lambda's timeout is derived from this as timeout\_seconds + 30, because the proxy holds the event stream open for the whole turn. | `number` | `300` | no |
| <a name="input_vpc_endpoints_to_create"></a> [vpc\_endpoints\_to\_create](#input\_vpc\_endpoints\_to\_create) | Interface endpoints to create in the VPC. Defaults to none, because in a shared VPC these usually already exist and only one endpoint per service per VPC may have private DNS enabled. Read it as "create the ones I do not already have". | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_amplify_app_id"></a> [amplify\_app\_id](#output\_amplify\_app\_id) | Amplify app ID, needed by aws amplify start-deployment |
| <a name="output_amplify_app_url"></a> [amplify\_app\_url](#output\_amplify\_app\_url) | URL the workbench is served from, once a build has been pushed. Empty until then: apply alone connects no repository and uploads no artifact. |
| <a name="output_harness_arn"></a> [harness\_arn](#output\_harness\_arn) | Harness ARN. This is what InvokeHarness takes; there is no harnessId parameter. |
| <a name="output_harness_execution_role_arn"></a> [harness\_execution\_role\_arn](#output\_harness\_execution\_role\_arn) | Execution role the harness assumes. A skill is code this role runs, so this is the identity to audit. |
| <a name="output_harness_id"></a> [harness\_id](#output\_harness\_id) | Harness ID |
| <a name="output_harness_memory_actual"></a> [harness\_memory\_actual](#output\_harness\_memory\_actual) | Memory configuration as the service reports it, rather than as configured. Compare against memory\_strategies when the agent answers normally but retains nothing between sessions — the quietest failure this module has, because a missing KMS grant produces exactly that with no error. |
| <a name="output_harness_name"></a> [harness\_name](#output\_harness\_name) | Derived harness name. AgentCore rejects dashes, so name\_prefix is underscored and suffixed — worth knowing because CLI calls take the name rather than the ARN, and it is not the same string as any other resource name here. |
| <a name="output_harness_security_group_id"></a> [harness\_security\_group\_id](#output\_harness\_security\_group\_id) | Security group on the harness ENIs. Deleting it is what blocks teardown for up to 8 hours after the harness goes away. |
| <a name="output_identity_pool_id"></a> [identity\_pool\_id](#output\_identity\_pool\_id) | Cognito Identity Pool ID |
| <a name="output_model_ids"></a> [model\_ids](#output\_model\_ids) | Models the proxy will accept a name for. Anything else is rejected rather than forwarded. |
| <a name="output_proxy_function_name"></a> [proxy\_function\_name](#output\_proxy\_function\_name) | Proxy Lambda the browser calls directly with Cognito credentials |
| <a name="output_proxy_log_group_name"></a> [proxy\_log\_group\_name](#output\_proxy\_log\_group\_name) | CloudWatch Logs group for the proxy Lambda. Worth having to hand: several failure modes in this module produce no error in the browser and are only visible here. |
| <a name="output_region"></a> [region](#output\_region) | Region the module was applied in, read from the provider. Exposed because the frontend needs it at build time and a script that guessed it would silently configure the browser to talk to the wrong region. |
| <a name="output_s3_gateway_endpoint_id"></a> [s3\_gateway\_endpoint\_id](#output\_s3\_gateway\_endpoint\_id) | S3 gateway endpoint this module created, or null if create\_s3\_gateway\_endpoint was false |
| <a name="output_shared_prefix"></a> [shared\_prefix](#output\_shared\_prefix) | Prefix the curated skills are stored under, readable by the harness and never by the browser |
| <a name="output_shared_skill_keys"></a> [shared\_skill\_keys](#output\_shared\_skill\_keys) | Objects Terraform placed under shared/, so a failed skill load can be checked against what should exist |
| <a name="output_skill_bucket_name"></a> [skill\_bucket\_name](#output\_skill\_bucket\_name) | Bucket holding authored skills under users/ and curated skills under shared/ |
| <a name="output_user_pool_client_id"></a> [user\_pool\_client\_id](#output\_user\_pool\_client\_id) | Cognito User Pool Client ID |
| <a name="output_user_pool_id"></a> [user\_pool\_id](#output\_user\_pool\_id) | Cognito User Pool ID |
| <a name="output_users_prefix"></a> [users\_prefix](#output\_users\_prefix) | Prefix a user's own skills are stored under. One source of truth for the frontend. |
| <a name="output_vpc_endpoint_ids"></a> [vpc\_endpoint\_ids](#output\_vpc\_endpoint\_ids) | Interface endpoints this module created, keyed by service name. Empty unless vpc\_endpoints\_to\_create was set. |
<!-- END_TF_DOCS -->