data "aws_iam_policy_document" "authenticated" {
  statement {
    sid       = "InvokeProxyOnly"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.proxy_lambda.lambda_function_arn]
  }
}


module "auth" {
  source = "./modules/cognito-user-pool"

  name = local.name

  authenticated_policy_json = [data.aws_iam_policy_document.authenticated.json]

  tags = var.tags
}

# No user is created. aws_cognito_user stores the password in state in plaintext
# whatever the variable is marked, so `make user` shells out to admin-create-user
# instead and the password never enters Terraform at all.
#
#   make user
#
# or directly, which is all that target does:
#
#   aws cognito-idp admin-create-user --user-pool-id <id> \
#     --username you@example.com --message-action SUPPRESS \
#     --user-attributes Name=email,Value=you@example.com Name=email_verified,Value=true
#   aws cognito-idp admin-set-user-password --user-pool-id <id> \
#     --username you@example.com --password '<password>' --permanent