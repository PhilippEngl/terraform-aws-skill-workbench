# Greenfield example: an empty account in, a working workbench out.
#
# This one creates the network itself — VPC, subnets, NAT gateway and route tables, in
# network.tf — and then hands it to the module, which creates the VPC endpoints AgentCore's
# VPC mode needs. It is the "I have nothing, show me it working" path, and unlike the
# complete example it applies as written with no identifiers to substitute.
#
# The module still creates no network of its own. That boundary does not move: everything
# in network.tf belongs to this example, and in a real account it belongs to whoever owns
# the VPC. See ../complete for the case where that is someone else.
#
# It costs real money while it exists. See the cost section in README.md before applying.

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

  vpc_id             = aws_vpc.this.id
  private_subnet_ids = aws_subnet.private[*].id

  # The whole difference from the complete example.
  #
  # ecr.api, ecr.dkr and logs are what VPC mode requires: the harness pulls its managed
  # container image from a private ECR repository in an AWS-owned account, and without them
  # sessions fail on an image pull timeout that names neither the endpoint nor the network.
  # kms and bedrock-agentcore are optional — those calls work over NAT — and are here
  # because keeping InvokeHarness off the public path is usually why VPC mode was chosen.
  #
  # In an existing VPC this list would mean "create the ones I do not already have", since
  # only one interface endpoint per service per VPC may have private DNS enabled. Here the
  # VPC is new, so all five are safe.
  vpc_endpoints_to_create = [
    "ecr.api",
    "ecr.dkr",
    "logs",
    "kms",
    "bedrock-agentcore",
  ]

  # A gateway endpoint is a route table entry rather than an ENI, so it is free and has no
  # security group — but it routes nothing until associated, which is why the module fails
  # the plan when the route table list is empty. network.tf creates exactly one private
  # route table, so this is a single-element list.
  create_s3_gateway_endpoint = true
  private_route_table_ids    = [aws_route_table.private.id]

  agent_model_id = var.agent_model_id

  # Everything else is left at the module's defaults, which is the point of this example:
  # the shortest configuration that actually stands up. The defaults include the tool
  # surface — file operations and the managed browser, with shell deliberately withheld.

  # The endpoints must exist before the harness tries to pull its image, and Terraform
  # cannot infer that: nothing the harness references depends on an endpoint. Without this
  # the first apply can create the harness first and fail at invoke time rather than at
  # apply, which reads as a broken agent rather than as an ordering problem.
  depends_on = [
    aws_route_table_association.private,
    aws_nat_gateway.this,
  ]
}
