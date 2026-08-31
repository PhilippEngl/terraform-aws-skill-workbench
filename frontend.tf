data "aws_iam_policy_document" "amplify_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "amplify" {
  name               = "${local.name}-amplify"
  description        = "Service role for the ${local.name} Amplify app"
  assume_role_policy = data.aws_iam_policy_document.amplify_assume.json

  tags = merge(var.tags, {
    Name = "${local.name}-amplify"
  })
}

resource "aws_amplify_app" "frontend" {
  name        = local.name
  description = "Skill workbench frontend"

  iam_service_role_arn = aws_iam_role.amplify.arn
  platform             = "WEB"

  # Used only if a repository is connected later. `make frontend` builds locally or in
  # CI and uploads the artifact, so this is here to keep the two paths consistent.
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - "**/*"
      cache:
        paths:
          - node_modules/**/*
  EOT

  # This is exactly the set frontend/src/config.ts reads
  environment_variables = {
    VITE_USER_POOL_ID        = module.auth.user_pool_id
    VITE_USER_POOL_CLIENT_ID = module.auth.user_pool_client_id
    VITE_IDENTITY_POOL_ID    = module.auth.identity_pool_id
    VITE_PROXY_FUNCTION_NAME = module.proxy_lambda.lambda_function_name
    VITE_MODEL_IDS           = join(",", local.model_ids)
    VITE_AWS_REGION          = data.aws_region.current.region
  }

  # Single page application: everything that is not a real file serves index.html.
  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }

  tags = merge(var.tags, {
    Name = local.name
  })
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.frontend.id
  branch_name = "main"
  stage       = "PRODUCTION"
  description = "Production branch for the ${local.name} frontend"

  tags = merge(var.tags, {
    Name = "${local.name}-main"
  })
}
