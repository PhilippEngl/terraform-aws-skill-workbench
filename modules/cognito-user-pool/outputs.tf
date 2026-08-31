output "user_pool_id" {
  description = "Cognito User Pool ID, for frontend configuration"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_client_id" {
  description = "Cognito User Pool Client ID, for frontend configuration"
  value       = aws_cognito_user_pool_client.this.id
}

output "identity_pool_id" {
  description = "Cognito Identity Pool ID, for frontend configuration"
  value       = aws_cognito_identity_pool.this.id
}
