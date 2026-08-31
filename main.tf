data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name           = "${var.name_prefix}-skill-workbench"
  agentcore_name = replace("${var.name_prefix}_skill_workbench", "-", "_")
  users_prefix   = "users"
  shared_prefix  = "shared"
  model_ids      = distinct(concat([var.agent_model_id], var.additional_agent_model_ids))

  skill_bucket_name = "${local.name}-skills-${data.aws_caller_identity.current.account_id}"
}

resource "aws_security_group" "lambda" {
  #checkov:skip=CKV2_AWS_5: "Attached via module module.proxy_lambda, as vpc_security_group_ids in proxy.tf. The graph check does not follow a reference into a child module."

  name        = "${local.name}-lambda-sg"
  description = "Egress for the VPC-attached proxy Lambda of the ${local.name} workbench"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to AWS APIs and VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-lambda-sg"
  })
}

resource "aws_security_group" "harness" {
  #checkov:skip=CKV2_AWS_5: "Attached via module module.harness, as security_group_ids in harness.tf. The graph check does not follow a reference into a child module."

  name        = "${local.name}-harness-sg"
  description = "AgentCore harness ENIs for the ${local.name} workbench"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to AWS APIs, VPC endpoints and the public web via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-harness-sg"
  })
}
