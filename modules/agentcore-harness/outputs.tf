output "harness_id" {
  description = "Harness ID, which the invoking client needs"
  value       = aws_bedrockagentcore_harness.this.harness_id
}

output "harness_arn" {
  description = "Harness ARN"
  value       = aws_bedrockagentcore_harness.this.arn
}

output "execution_role_arn" {
  description = "ARN of the execution role the harness assumes"
  value       = aws_iam_role.this.arn
}

output "memory_actual" {
  description = "Deployed memory configuration as reported by the service"
  value       = aws_bedrockagentcore_harness.this.memory_actual
}
