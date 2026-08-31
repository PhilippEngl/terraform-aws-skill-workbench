mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  mock_data "aws_iam_policy" {
    defaults = {
      policy = "{}"
    }
  }
}

variables {
  vpc_id             = "vpc-00000000000000000"
  private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  agent_model_id     = "eu.anthropic.claude-sonnet-4-6"
}


run "derived_harness_name_is_legal_at_the_longest_prefix" {
  command = plan

  variables {
    name_prefix = "abcdefghij-klmnopqrs" # 20 characters, dashes included
  }

  assert {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,39}$", output.harness_name))
    error_message = "Derived harness name must match ^[a-zA-Z][a-zA-Z0-9_]{0,39}$. AgentCore rejects dashes and anything over 40 characters."
  }

  assert {
    condition     = output.harness_name == "abcdefghij_klmnopqrs_skill_workbench"
    error_message = "Dashes in name_prefix must become underscores in the harness name."
  }
}

run "out_of_range_temperature_is_rejected" {
  command = plan

  variables {
    agent_model_temperature = 1.5
  }

  expect_failures = [var.agent_model_temperature]
}

run "zero_top_p_is_rejected" {
  command = plan

  variables {
    agent_model_top_p = 0
  }

  expect_failures = [var.agent_model_top_p]
}

run "unknown_vpc_endpoint_service_is_rejected" {
  command = plan

  variables {
    vpc_endpoints_to_create = ["ecr.api", "sqs"]
  }

  expect_failures = [var.vpc_endpoints_to_create]
}

run "s3_gateway_endpoint_without_route_tables_is_rejected" {
  command = plan

  variables {
    create_s3_gateway_endpoint = true
    private_route_table_ids    = []
  }

  expect_failures = [aws_vpc_endpoint.s3]
}

run "s3_gateway_endpoint_with_route_tables_is_accepted" {
  command = plan

  variables {
    create_s3_gateway_endpoint = true
    private_route_table_ids    = ["rtb-00000000000000001"]
  }

  assert {
    condition     = length(aws_vpc_endpoint_route_table_association.s3) == 1
    error_message = "One route table association per entry in private_route_table_ids."
  }
}
