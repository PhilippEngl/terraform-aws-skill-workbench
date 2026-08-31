data "aws_iam_policy_document" "harness_storage" {
  statement {
    sid     = "ReadSkills"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${module.skill_bucket.bucket_arn}/${local.users_prefix}/*",
      "${module.skill_bucket.bucket_arn}/${local.shared_prefix}/*",
    ]
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
    sid    = "UseSkillsKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = [module.skills_key.key_arn]
  }

  statement {
    sid       = "DenyRoleAssumption"
    effect    = "Deny"
    actions   = ["sts:AssumeRole"]
    resources = ["*"]
  }
}

module "harness" {
  source = "./modules/agentcore-harness"

  name          = local.agentcore_name
  model_id      = var.agent_model_id
  system_prompt = var.system_prompt

  additional_model_ids = var.additional_agent_model_ids

  network_mode       = "VPC"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.harness.id]

  browser_tool_name = var.enable_browser_tool ? "browser" : null
  allowed_tools     = var.allowed_tools

  max_iterations  = var.max_iterations
  timeout_seconds = var.timeout_seconds

  max_tokens        = var.agent_max_tokens
  model_max_tokens  = var.agent_model_max_tokens
  model_temperature = var.agent_model_temperature
  model_top_p       = var.agent_model_top_p

  memory_strategies            = var.memory_strategies
  memory_event_expiry_duration = var.memory_event_expiry_days
  memory_encryption_key_arn    = module.skills_key.key_arn

  additional_policy_json = [data.aws_iam_policy_document.harness_storage.json]

  tags = var.tags
}
