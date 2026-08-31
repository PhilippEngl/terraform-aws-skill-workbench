terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.61, < 7.0"
    }
  }
}

resource "aws_cognito_user_pool" "this" {
  name = var.name

  admin_create_user_config {
    allow_admin_create_user_only = !var.self_signup_enabled
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = var.password_minimum_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.name}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Returns a generic error rather than revealing whether an account exists.
  prevent_user_existence_errors = "ENABLED"

  # Public client for a browser SPA, so no secret.
  generate_secret = false
}

resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = var.name
  allow_unauthenticated_identities = false

  cognito_identity_providers {
    client_id     = aws_cognito_user_pool_client.this.id
    provider_name = aws_cognito_user_pool.this.endpoint
  }

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Role the browser assumes after login, via web identity federation. Its policies
# are what the frontend can do directly, so they are the tightest thing here.
data "aws_iam_policy_document" "authenticated_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["cognito-identity.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "cognito-identity.amazonaws.com:aud"
      values   = [aws_cognito_identity_pool.this.id]
    }

    condition {
      test     = "ForAnyValue:StringLike"
      variable = "cognito-identity.amazonaws.com:amr"
      values   = ["authenticated"]
    }
  }
}

resource "aws_iam_role" "authenticated" {
  name               = "${var.name}-authenticated"
  description        = "Assumed by authenticated users of the ${var.name} identity pool"
  assume_role_policy = data.aws_iam_policy_document.authenticated_assume.json

  tags = merge(var.tags, {
    Name = "${var.name}-authenticated"
  })
}

resource "aws_iam_role_policy" "authenticated" {
  count = length(var.authenticated_policy_json)

  name   = "authenticated-${count.index}"
  role   = aws_iam_role.authenticated.id
  policy = var.authenticated_policy_json[count.index]
}

resource "aws_cognito_identity_pool_roles_attachment" "this" {
  identity_pool_id = aws_cognito_identity_pool.this.id

  roles = {
    authenticated = aws_iam_role.authenticated.arn
  }
}
