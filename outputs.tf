output "region" {
  description = "Region the module was applied in, read from the provider. Exposed because the frontend needs it at build time and a script that guessed it would silently configure the browser to talk to the wrong region."
  value       = data.aws_region.current.region
}

output "amplify_app_url" {
  description = "URL the workbench is served from, once a build has been pushed. Empty until then: apply alone connects no repository and uploads no artifact."
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.frontend.default_domain}"
}

output "amplify_app_id" {
  description = "Amplify app ID, needed by aws amplify start-deployment"
  value       = aws_amplify_app.frontend.id
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.auth.user_pool_id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.auth.user_pool_client_id
}

output "identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = module.auth.identity_pool_id
}

output "skill_bucket_name" {
  description = "Bucket holding authored skills under users/ and curated skills under shared/"
  value       = module.skill_bucket.bucket_id
}

output "harness_id" {
  description = "Harness ID"
  value       = module.harness.harness_id
}

output "harness_name" {
  description = "Derived harness name. AgentCore rejects dashes, so name_prefix is underscored and suffixed — worth knowing because CLI calls take the name rather than the ARN, and it is not the same string as any other resource name here."
  value       = local.agentcore_name
}

output "harness_arn" {
  description = "Harness ARN. This is what InvokeHarness takes; there is no harnessId parameter."
  value       = module.harness.harness_arn
}

output "harness_execution_role_arn" {
  description = "Execution role the harness assumes. A skill is code this role runs, so this is the identity to audit."
  value       = module.harness.execution_role_arn
}

output "proxy_function_name" {
  description = "Proxy Lambda the browser calls directly with Cognito credentials"
  value       = module.proxy_lambda.lambda_function_name
}

output "proxy_log_group_name" {
  description = "CloudWatch Logs group for the proxy Lambda. Worth having to hand: several failure modes in this module produce no error in the browser and are only visible here."
  value       = module.proxy_lambda.lambda_cloudwatch_log_group_name
}

output "harness_memory_actual" {
  description = "Memory configuration as the service reports it, rather than as configured. Compare against memory_strategies when the agent answers normally but retains nothing between sessions — the quietest failure this module has, because a missing KMS grant produces exactly that with no error."
  value       = module.harness.memory_actual
}

output "users_prefix" {
  description = "Prefix a user's own skills are stored under. One source of truth for the frontend."
  value       = local.users_prefix
}

output "shared_prefix" {
  description = "Prefix the curated skills are stored under, readable by the harness and never by the browser"
  value       = local.shared_prefix
}

output "shared_skill_keys" {
  description = "Objects Terraform placed under shared/, so a failed skill load can be checked against what should exist"
  value       = sort([for o in aws_s3_object.shared_skill : o.key])
}

output "model_ids" {
  description = "Models the proxy will accept a name for. Anything else is rejected rather than forwarded."
  value       = local.model_ids
}

output "harness_security_group_id" {
  description = "Security group on the harness ENIs. Deleting it is what blocks teardown for up to 8 hours after the harness goes away."
  value       = aws_security_group.harness.id
}

output "vpc_endpoint_ids" {
  description = "Interface endpoints this module created, keyed by service name. Empty unless vpc_endpoints_to_create was set."
  value       = { for service, endpoint in aws_vpc_endpoint.interface : service => endpoint.id }
}

output "s3_gateway_endpoint_id" {
  description = "S3 gateway endpoint this module created, or null if create_s3_gateway_endpoint was false"
  value       = var.create_s3_gateway_endpoint ? aws_vpc_endpoint.s3[0].id : null
}
