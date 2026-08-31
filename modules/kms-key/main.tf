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


data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_109: "Consumed only as the policy of resource aws_kms_key.this in this module. A wildcard resource in a key policy scopes to that one key, not to the account, because the document is attached to the key rather than to an identity."
  #checkov:skip=CKV_AWS_111: "Consumed only as the policy of resource aws_kms_key.this in this module. A wildcard resource in a key policy scopes to that one key, not to the account, because the document is attached to the key rather than to an identity."
  #checkov:skip=CKV_AWS_356: "Consumed only as the policy of resource aws_kms_key.this in this module. A wildcard resource in a key policy scopes to that one key, and the account-root statement is the AWS default key policy: without it the key cannot be administered through IAM and becomes unmanageable."

  statement {
    sid    = "EnableIAMPolicies"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []

    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []

    content {
      sid    = "AllowServiceUsage"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = var.service_principals
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = var.enable_key_rotation
  deletion_window_in_days = var.deletion_window_in_days
  policy                  = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
