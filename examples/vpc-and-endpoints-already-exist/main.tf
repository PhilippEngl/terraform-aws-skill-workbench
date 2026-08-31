# Complete example: an existing VPC that already has the VPC endpoints the harness
# needs, which is the normal situation in an organisation where a platform team owns the
# network.
#
# This is a template, not a runnable configuration. The identifiers below are
# placeholders and no AWS account contains them — copy this directory, put your own in
# terraform.tfvars, and read the four prerequisites in the README before applying.
#
# It is also the directory the module's Makefile points TF_DIR at by default, so
# `make frontend`, `make frontend-env` and `make user` read their inputs from here.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.61, < 7.0"
    }
  }

  # No backend. An example uses local state deliberately: a backend belongs to whoever
  # adopts this, and a committed backend block is one more thing to delete.
}

provider "aws" {
  region = var.aws_region

  # Applied by the provider to every resource that supports tagging, including resources
  # inside the module. The module also takes a `tags` variable; either works, and using
  # both is fine because the module merges rather than replaces.
  default_tags {
    tags = {
      Project   = "skill-workbench"
      ManagedBy = "Terraform"
    }
  }
}

module "skill_workbench" {
  source = "../../"

  name_prefix = var.name_prefix

  # Required, with no defaults. Private subnets with a NAT route: a harness ENI gets no
  # public IP, so a public subnet leaves it with no egress path at all.
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  # Nothing is created here, which is what makes this the "complete" example: the VPC is
  # assumed to already have interface endpoints for ecr.api, ecr.dkr and logs, and a
  # route to S3. Those are not optional for VPC mode however you provide them — without
  # them the harness fails on image pull timeout, with an error that names neither the
  # missing endpoint nor the network.
  #
  # kms and bedrock-agentcore are optional. Without them those calls leave through NAT,
  # which works; adding them keeps the traffic off the public path.
  vpc_endpoints_to_create    = []
  create_s3_gateway_endpoint = false

  # Required. No single model ID is available in every region, and a geo prefix selects
  # which regions inference may run in, so this has to match where you are deploying.
  agent_model_id = var.agent_model_id

  # Every model the picker offers needs an entry here, because a per-invocation model
  # replaces the configured one rather than supplementing it — a model named only by the
  # caller still needs the execution role's permission.
  additional_agent_model_ids = var.additional_agent_model_ids

  # 300 seconds of harness turn. The proxy Lambda's own timeout is derived as this plus
  # 30, so it cannot be set below the turn it has to outlive.
  timeout_seconds = 300
  max_iterations  = 15

  # Only needed while serving the frontend from a laptop with `make frontend-dev`. Drop
  # it for a deployment nobody develops against.
  frontend_dev_origins = ["http://localhost:5173"]

  tags = {
    Environment = "dev"
    Owner       = "platform-team"
  }
}
