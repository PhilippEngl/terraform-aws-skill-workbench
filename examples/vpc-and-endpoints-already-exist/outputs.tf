# Re-exported rather than left inside the module, because the Makefile's TF_DIR points
# here and the scripts read these by name with `terraform output -raw`. The first five
# plus the region are what scripts/frontend-env.sh needs; removing any of them breaks
# `make frontend` with an error about a missing output rather than a missing variable.

output "region" {
  description = "Region the module was applied in. Read by scripts/frontend-env.sh, so the browser cannot be configured for a different region than the backend."
  value       = module.skill_workbench.region
}

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.skill_workbench.user_pool_id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID"
  value       = module.skill_workbench.user_pool_client_id
}

output "identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = module.skill_workbench.identity_pool_id
}

output "proxy_function_name" {
  description = "Proxy Lambda the browser invokes with Cognito credentials"
  value       = module.skill_workbench.proxy_function_name
}

output "model_ids" {
  description = "Models the proxy accepts a name for"
  value       = module.skill_workbench.model_ids
}

output "amplify_app_id" {
  description = "Amplify app ID, used by scripts/deploy-frontend.sh"
  value       = module.skill_workbench.amplify_app_id
}

output "amplify_app_url" {
  description = "URL the workbench is served from. Serves nothing until `make frontend` has pushed a build — apply alone connects no repository."
  value       = module.skill_workbench.amplify_app_url
}

# --- Operating and debugging --------------------------------------------------

output "skill_bucket_name" {
  description = "Bucket holding authored skills under users/ and curated skills under shared/"
  value       = module.skill_workbench.skill_bucket_name
}

output "harness_name" {
  description = "Derived harness name, which is what the AgentCore CLI takes"
  value       = module.skill_workbench.harness_name
}

output "harness_arn" {
  description = "Harness ARN, which is what InvokeHarness takes"
  value       = module.skill_workbench.harness_arn
}

output "shared_skill_keys" {
  description = "What Terraform placed under shared/, so a failed skill load can be checked against what should exist"
  value       = module.skill_workbench.shared_skill_keys
}

output "harness_security_group_id" {
  description = "Deleting this group is what blocks teardown for up to 8 hours after the harness goes away. See the teardown section of the module README."
  value       = module.skill_workbench.harness_security_group_id
}
