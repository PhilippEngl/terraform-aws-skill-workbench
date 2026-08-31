data "aws_iam_policy_document" "proxy_lambda" {
  statement {
    sid    = "WriteAuthoredSkills"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${module.skill_bucket.bucket_arn}/${local.users_prefix}/*"]
  }

  statement {
    sid       = "ListSkillPrefixes"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.skill_bucket.bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values = [
        "${local.users_prefix}/*",
        "${local.shared_prefix}/*",
      ]
    }
  }

  statement {
    sid       = "ReadSharedSkills"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.skill_bucket.bucket_arn}/${local.shared_prefix}/*"]
  }

  statement {
    sid    = "UseSkillsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [module.skills_key.key_arn]
  }

  statement {
    sid    = "InvokeHarness"
    effect = "Allow"

    actions = [
      "bedrock-agentcore:InvokeHarness",
      "bedrock-agentcore:InvokeAgentRuntime",
    ]

    resources = [
      module.harness.harness_arn,
      "${module.harness.harness_arn}/*",
    ]
  }
}

module "proxy_lambda" {
  #checkov:skip=CKV_TF_1: "A registry source has no commit to pin — the check cannot be satisfied without fetching this module over git instead, which costs the version argument and the registry's constraint handling. version = 8.8.0 is the strongest pin this source type allows, and it removes the common failure mode: drifting to a new minor on a fresh init months later. The residual risk it does not cover is a force-pushed v8.8.0 tag upstream. Revisit with a git source pinned to a SHA if this module is ever part of something shipped rather than a workbench."

  source  = "terraform-aws-modules/lambda/aws"
  version = "8.8.0"

  function_name = "${local.name}-proxy"
  description   = "Security boundary between browser credentials and the harness API"

  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]

  source_path = [{
    path             = abspath("${path.module}/lambda/proxy")
    pip_requirements = true
    patterns = [
      "!.*/__pycache__/.*",
      "!.*\\.pyc",
    ]
  }]

  artifacts_dir            = "${path.root}/.terraform/tmp"
  recreate_missing_package = false
  timeout                  = var.timeout_seconds
  memory_size              = 512

  environment_variables = {
    HARNESS_ARN             = module.harness.harness_arn
    BUCKET_NAME             = module.skill_bucket.bucket_id
    KMS_KEY_ARN             = module.skills_key.key_arn
    USERS_PREFIX            = local.users_prefix
    SHARED_PREFIX           = local.shared_prefix
    ALLOWED_MODEL_IDS       = join(",", local.model_ids)
    DEFAULT_MODEL_ID        = var.agent_model_id
    POWERTOOLS_SERVICE_NAME = "${local.name}-proxy"
    POWERTOOLS_LOG_LEVEL    = var.log_level
  }

  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda.id]
  attach_network_policy  = true

  attach_policy_jsons    = true
  policy_jsons           = [data.aws_iam_policy_document.proxy_lambda.json]
  number_of_policy_jsons = 1

  attach_cloudwatch_logs_policy      = true
  attach_create_log_group_permission = false
  cloudwatch_logs_retention_in_days  = var.log_retention_days

  tags = var.tags
}
