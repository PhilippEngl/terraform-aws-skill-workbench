# Greenfield example

Deploys the workbench into a VPC that does not yet have the endpoints AgentCore's VPC mode needs, and lets the module create them.

"Greenfield" describes the endpoints, not the VPC. **The module never creates a VPC, subnets, NAT gateways or route tables.** Those stay with whoever owns the account, because that is where the blast radius of getting them wrong belongs. You still supply `vpc_id`, `private_subnet_ids` and `private_route_table_ids`.

This is a template: the identifiers are placeholders that exist in no account.

## What it creates beyond the complete example

Five interface endpoints — `ecr.api`, `ecr.dkr`, `logs`, `kms` and `bedrock-agentcore` — with one security group allowing 443 from the VPC CIDR, plus an S3 gateway endpoint associated with each route table you name.

The first three are what VPC mode requires: the harness pulls its managed container image from a private ECR repository in an AWS-owned account, and without them sessions fail on image pull timeout. The last two are optional — without them those calls leave through NAT, which works — and are here because keeping `InvokeHarness` off the public path is usually the reason someone chose VPC mode in the first place.

## Two things to check before applying

**Only one interface endpoint per service per VPC may have private DNS enabled.** So `vpc_endpoints_to_create` means "create the ones I do not already have". If the VPC already has, say, a `logs` endpoint, remove `logs` from the list — otherwise apply fails with an error about private DNS rather than about duplication.

**A gateway endpoint is VPC-wide.** It changes S3 routing for every workload in the route tables you associate it with, not only for this module's resources. In a shared VPC that is a change to other people's traffic, and `terraform destroy` removes it again. If that is not acceptable, set `create_s3_gateway_endpoint = false` and have the network owner create it.

## Running it

```sh
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform apply
```

Then `make user` and `make frontend` from the module root, with `TF_DIR=examples/greenfield`:

```sh
make user     TF_DIR=examples/greenfield
make frontend TF_DIR=examples/greenfield
```

`TF_DIR` defaults to `examples/complete`, so it has to be passed here. Until `make frontend` has run once, `amplify_app_url` returns a URL that 404s: no repository is connected, so Amplify never builds anything itself.

## Cost note

Each interface endpoint bills per ENI per hour, and this example creates one ENI per endpoint per subnet — five endpoints across two subnets is ten ENIs, before any agent runs. The S3 gateway endpoint is free.
