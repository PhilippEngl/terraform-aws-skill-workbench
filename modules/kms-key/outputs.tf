output "key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.this.arn
}
