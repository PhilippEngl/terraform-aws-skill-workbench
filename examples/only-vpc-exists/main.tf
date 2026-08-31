# Greenfield example: a VPC with no endpoints yet, where the module creates the network
# plumbing the harness needs.
#
# "Greenfield" describes the endpoints, not the VPC. The module never creates a VPC,
# subnets, NAT gateways or route tables — those are the caller's, because the blast radius
# of getting them wrong belongs to whoever owns the account.
#
# This is a template. The identifiers below are placeholders and no AWS account contains
# them.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.61, < 7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

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

  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids

  # The whole difference from the complete example.
  #
  # Read this list as "create the ones I do not already have". Only one interface endpoint
  # per service per VPC may have private DNS enabled, so naming a service that already has
  # one fails at apply — and the failure is about DNS, not about duplication.
  #
  # ecr.api, ecr.dkr and logs are what VPC mode requires. kms and bedrock-agentcore are
  # optional: without them those calls leave through NAT, which works, but keeping
  # InvokeHarness off the public path is the reason to have them.
  vpc_endpoints_to_create = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "kms",
    "bedrock-agentcore",
  ]

  # A gateway endpoint is a route table entry rather than an ENI, so it costs nothing and
  # has no security group — but it is only useful once associated, which is why the module
  # fails the plan if the route table list is empty.
  #
  # Note this is VPC-wide. In a shared VPC it changes routing for workloads this module
  # knows nothing about, and destroying the module removes it again.
  create_s3_gateway_endpoint = true
  private_route_table_ids    = var.private_route_table_ids

  agent_model_id = var.agent_model_id

  # Everything else is left at the module's defaults, which is the point of this example:
  # the shortest configuration that actually stands up. The defaults include the tool
  # surface — file operations and the managed browser, with shell deliberately withheld.
}
