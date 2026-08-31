# Complete example

Deploys the workbench into a VPC you already have, and creates no networking of its own. This is the normal case in an organisation where a platform team owns the network, and it is the directory the module's `Makefile` reads Terraform outputs from by default.

This is a template. The VPC and subnet identifiers are placeholders that exist in no account, so an apply fails immediately rather than creating anything in the wrong place. Copy `terraform.tfvars.example` to `terraform.tfvars` and replace them.

## Four prerequisites

The module cannot detect any of these, and three of the four fail in ways that do not name the cause.

1. **Interface VPC endpoints for `ecr.api`, `ecr.dkr` and `logs`.** The harness runs in VPC mode, which is egress-only, and it pulls its managed container image from a private ECR repository in an AWS-owned account. Without these, sessions fail on image pull timeout.
2. **A route to S3**, either a gateway endpoint associated with your private route tables or an interface endpoint. Skills are fetched from S3 at session start by the harness, and the proxy enumerates them before every invocation.
3. **Private subnets with a NAT route.** Not a recommendation. A harness ENI is assigned no public IP, so a public subnet leaves it with no egress path at all.
4. **A model that exists in your region.** `agent_model_id` is required and has no default because no single model ID is available everywhere. A geo prefix such as `us.` or `eu.` selects a cross-region inference profile and determines which regions inference may run in, so it must match the geography of your region.

If your VPC is missing the endpoints, use the [`greenfield`](../greenfield) example instead, which creates them.

## Running it

```sh
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform apply
```

Then, from the module root:

```sh
make user       # create a Cognito user, interactively
make frontend   # build the React app and push it to Amplify
```

`terraform apply` alone leaves an Amplify app with nothing to serve. No repository is connected, so Amplify never builds anything itself and `amplify_app_url` returns a URL that 404s until `make frontend` has run once.

## Teardown

`terraform destroy` fails on the two security groups for up to eight hours after the harness is deleted, because AgentCore's service-owned ENIs persist and a security group cannot be deleted while an ENI references it. The ordered sequence is in the module README; `harness_security_group_id` is exported here so you can watch for the ENIs to clear.
