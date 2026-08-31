variable "name" {
  description = "Bucket name. S3 bucket names are globally unique, so include the account ID or another discriminator."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SSE-KMS. Leave null for SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "versioning_enabled" {
  description = "Whether object versioning is enabled"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Whether terraform destroy may delete a bucket that still contains objects. False is the safe default. This module sets it true for the skill bucket so that a destroy leaves nothing billable behind, which is the right trade for authored content you can re-create and the wrong one for anything you cannot."
  type        = bool
  default     = false
}

variable "lifecycle_enabled" {
  description = "Whether to create the lifecycle rules that abort stale multipart uploads and expire noncurrent versions"
  type        = bool
  default     = true
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after which incomplete multipart uploads are aborted. These are invisible in the console and billed until removed."
  type        = number
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which noncurrent object versions are deleted"
  type        = number
  default     = 30
}

variable "cors_rules" {
  description = "CORS rules. Needed when a browser uploads directly to the bucket, as the image editing frontend does."
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string))
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}

variable "logging_target_bucket" {
  description = "Bucket that receives S3 server access logs for this bucket. Null disables access logging. The target must be in the same region and account, must not use SSE-KMS, and must grant s3:PutObject to logging.s3.amazonaws.com — all three are AWS constraints on log delivery, and violating any of them fails silently by simply never delivering a log."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Key prefix for delivered access logs. Include the trailing slash; without it the date is concatenated onto the prefix rather than nested under it."
  type        = string
  default     = null
}

variable "eventbridge_notifications" {
  description = "Whether object-level events are sent to EventBridge. Enabling this bills nothing by itself: events go to the default bus and are discarded unless a rule matches. Turn it off only for a bucket nothing should ever react to, such as a log destination."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates, merged with its own Name tag. A module cannot use the provider's default_tags, so tagging is explicit."
  type        = map(string)
  default     = {}
}
