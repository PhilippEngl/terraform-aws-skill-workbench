output "vpc_id" {
  description = "VPC this example created. In the complete example this is an input you supply."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnets this example created, one per availability zone, each with a NAT route"
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Route tables the S3 gateway endpoint is associated with. One here, because there is one NAT gateway for the private subnets to point at."
  value       = [aws_route_table.private.id]
}

output "nat_gateway_public_ip" {
  description = "Public address the harness egresses from. Worth having when an allowlist somewhere else needs to permit it."
  value       = aws_eip.nat.public_ip
}

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

# Read by `make destroy`, which polls until no ENI references this group. AgentCore's
# service-owned ENIs outlive the harness by up to eight hours and block the group's
# deletion, so a single-pass destroy fails without this wait.
output "harness_security_group_id" {
  description = "Security group on the harness ENIs. Needed during teardown to poll for ENI release."
  value       = module.skill_workbench.harness_security_group_id
}
