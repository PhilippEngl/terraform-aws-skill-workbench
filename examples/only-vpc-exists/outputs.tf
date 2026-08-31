# The five the frontend tooling reads, plus the endpoints this example creates — because
# the endpoint IDs are the thing worth checking here, and the reason to prefer this
# example over the complete one.

output "region" {
  description = "Region the module was applied in. Read by scripts/frontend-env.sh."
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
  description = "URL the workbench is served from, once `make frontend` has pushed a build"
  value       = module.skill_workbench.amplify_app_url
}

output "vpc_endpoint_ids" {
  description = "Interface endpoints this example created, keyed by service name"
  value       = module.skill_workbench.vpc_endpoint_ids
}

output "s3_gateway_endpoint_id" {
  description = "The S3 gateway endpoint this example created"
  value       = module.skill_workbench.s3_gateway_endpoint_id
}
