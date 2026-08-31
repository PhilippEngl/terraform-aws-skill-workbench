terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.61, < 7.0"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

locals {
  # Every model the harness may actually use. The configured model is not enough:
  # InvokeHarness accepts a per-invocation `model` parameter that replaces it
  # entirely, so any model a caller may name needs permission here too. Missing one
  # produces an AccessDenied only for the requests that override.
  all_model_ids = distinct(concat([var.model_id], var.additional_model_ids))

  # Invoking through an inference profile needs permission on the profile ARN AND on
  # the underlying foundation model, so the geo or global prefix is stripped to build
  # the second ARN. Granting only the profile produces an AccessDenied that reads
  # like a model-access problem.
  model_resources = distinct(flatten([
    for id in local.all_model_ids : [
      "arn:${data.aws_partition.current.partition}:bedrock:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:inference-profile/${id}",
      "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/${replace(id, "/^(eu|us|global)\\./", "")}",
    ]
  ]))
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-execution"
  description        = "Execution role assumed by the ${var.name} AgentCore harness"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = merge(var.tags, {
    Name = "${var.name}-execution"
  })
}

data "aws_iam_policy_document" "model" {
  statement {
    sid    = "InvokeConfiguredModel"
    effect = "Allow"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]

    resources = local.model_resources
  }
}

resource "aws_iam_role_policy" "model" {
  name   = "model"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.model.json
}

# Managed memory is provisioned by the service, so the ARN is not known at plan
# time and these are scoped to the account's memory resources in this region.
data "aws_iam_policy_document" "memory" {
  statement {
    sid    = "ManageConversationMemory"
    effect = "Allow"

    actions = [
      "bedrock-agentcore:GetMemory",
      "bedrock-agentcore:ListEvents",
      "bedrock-agentcore:GetEvent",
      "bedrock-agentcore:CreateEvent",
      "bedrock-agentcore:PutEvents",
      "bedrock-agentcore:DeleteEvent",
      "bedrock-agentcore:CreateSession",
      "bedrock-agentcore:GetSession",
      "bedrock-agentcore:UpdateSession",
      "bedrock-agentcore:DeleteSession",
      "bedrock-agentcore:ListSessions",
      "bedrock-agentcore:ListActors",
      "bedrock-agentcore:RetrieveMemoryRecords",
      "bedrock-agentcore:ListMemoryRecords",
      "bedrock-agentcore:GetMemoryRecord",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:memory/*",
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:runtime/*",
    ]
  }
}

resource "aws_iam_role_policy" "memory" {
  name   = "memory"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.memory.json
}

# The documented baseline for a harness execution role, beyond above
data "aws_iam_policy_document" "baseline" {
  statement {
    sid    = "Observability"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock-agentcore/runtimes/*"]
  }

  statement {
    sid       = "LogResourcePolicy"
    effect    = "Allow"
    actions   = ["logs:PutResourcePolicy"]
    resources = ["*"]
  }

  statement {
    sid    = "Tracing"
    effect = "Allow"

    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
    ]

    resources = ["*"]
  }

  statement {
    sid       = "Metrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["bedrock-agentcore"]
    }
  }

  statement {
    sid    = "WorkloadIdentityToken"
    effect = "Allow"

    actions = [
      "bedrock-agentcore:GetWorkloadAccessToken",
      "bedrock-agentcore:GetWorkloadAccessTokenForJWT",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default",
      "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workload-identity-directory/default/workload-identity/harness_${var.name}-*",
    ]
  }

  statement {
    sid    = "PullManagedImage"
    effect = "Allow"

    actions = [
      "ecr-public:GetAuthorizationToken",
      "sts:GetServiceBearerToken",
    ]

    resources = ["*"]

    # Neither action supports resource-level permissions, so the wildcard cannot be
    # narrowed and the only constraint available is a condition. This bounds a token
    # that would otherwise be requestable in any region.
    #
    # us-east-1 is listed alongside the deployment region deliberately: the ECR Public
    # API is not regional in the way ECR is, and sts:GetServiceBearerToken reached
    # through the global STS endpoint evaluates aws:RequestedRegion as us-east-1. Pinning
    # to the deployment region alone would deny the image pull outside us-east-1, and it
    # would do so as the eight-minute session timeout described in the README rather than
    # as an access-denied error.
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = distinct([data.aws_region.current.region, "us-east-1"])
    }
  }

  dynamic "statement" {
    for_each = var.network_mode == "VPC" ? [1] : []

    content {
      sid       = "PullManagedImageFromPrivateEcr"
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]

      # ECR is regional and the repository this token is used against is already pinned to
      # the deployment region in PullManagedImageLayers below, so a token issued for any
      # other region could not be spent here. Pinning it costs nothing and keeps the two
      # statements consistent.
      condition {
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = [data.aws_region.current.region]
      }
    }
  }

  dynamic "statement" {
    for_each = var.network_mode == "VPC" ? [1] : []

    content {
      sid    = "PullManagedImageLayers"
      effect = "Allow"

      actions = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]

      resources = ["arn:${data.aws_partition.current.partition}:ecr:${data.aws_region.current.region}:*:repository/harness-*"]
    }
  }

  dynamic "statement" {
    for_each = var.browser_tool_name != null ? [1] : []

    content {
      sid    = "UseManagedBrowser"
      effect = "Allow"

      actions = [
        "bedrock-agentcore:StartBrowserSession",
        "bedrock-agentcore:GetBrowserSession",
        "bedrock-agentcore:ListBrowserSessions",
        "bedrock-agentcore:StopBrowserSession",
        "bedrock-agentcore:ConnectBrowserAutomationStream",
        "bedrock-agentcore:ConnectBrowserLiveViewStream",
      ]

      resources = [
        "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:aws:browser/*",
        "arn:${data.aws_partition.current.partition}:bedrock-agentcore:${data.aws_region.current.region}:aws:browser-custom/*",
      ]
    }
  }

  statement {
    sid    = "DenyUnverifiedUserIdDelegation"
    effect = "Deny"

    actions = [
      "bedrock-agentcore:GetWorkloadAccessTokenForUserId",
      "bedrock-agentcore:InvokeAgentRuntimeForUser",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "baseline" {
  name   = "baseline"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.baseline.json
}

resource "aws_iam_role_policy" "additional" {
  count = length(var.additional_policy_json)

  name   = "additional-${count.index}"
  role   = aws_iam_role.this.id
  policy = var.additional_policy_json[count.index]
}

resource "aws_bedrockagentcore_harness" "this" {
  harness_name       = var.name
  execution_role_arn = aws_iam_role.this.arn

  max_iterations  = var.max_iterations
  timeout_seconds = var.timeout_seconds
  max_tokens      = var.max_tokens

  # Scoping this is a cost lever as well as a security one: tool definitions count
  # as model input tokens on every request even when never called.
  allowed_tools = var.allowed_tools

  environment_variables = var.environment_variables

  model {
    bedrock_model_config {
      model_id    = var.model_id
      max_tokens  = var.model_max_tokens
      temperature = var.model_temperature
      top_p       = var.model_top_p
    }
  }

  system_prompt {
    text = var.system_prompt
  }

  dynamic "tool" {
    for_each = var.browser_tool_name != null ? [var.browser_tool_name] : []

    content {
      type = "agentcore_browser"
      name = tool.value

      config {
        agentcore_browser {}
      }
    }
  }

  # VPC mode is not a top-level block on the harness the way it is on the runtime.
  # It sits under environment.agentcore_runtime_environment, because the harness is a
  # managed abstraction over Runtime and this is Runtime's own configuration surface
  # showing through. Only emitted for VPC, so a PUBLIC harness plans no environment
  # block at all rather than an empty one.
  dynamic "environment" {
    for_each = var.network_mode == "VPC" ? [1] : []

    content {
      agentcore_runtime_environment {
        network_configuration {
          network_mode = "VPC"

          network_mode_config {
            subnets         = var.subnet_ids
            security_groups = var.security_group_ids
          }
        }
      }
    }
  }

  # Configured explicitly rather than left to default, so retention and strategies
  # are visible. Clearing this block resets deployed config to defaults, which is
  # what environment_actual and memory_actual exist to expose.
  memory {
    managed_memory_configuration {
      event_expiry_duration = var.memory_event_expiry_duration
      encryption_key_arn    = var.memory_encryption_key_arn
      strategies            = var.memory_strategies
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  depends_on = [
    aws_iam_role_policy.model,
    aws_iam_role_policy.memory,
    aws_iam_role_policy.baseline,
    aws_iam_role_policy.additional,
  ]
}
