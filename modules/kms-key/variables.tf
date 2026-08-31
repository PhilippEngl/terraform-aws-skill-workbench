variable "name" {
  description = "Resource name, also used for the alias as alias/<name>"
  type        = string
}

variable "description" {
  description = "Description of what this key encrypts"
  type        = string
  default     = "Customer managed key"
}

variable "enable_key_rotation" {
  description = "Whether to rotate the key material annually"
  type        = bool
  default     = true
}

variable "deletion_window_in_days" {
  description = "Days AWS waits before deleting the key after destroy. 7 is the minimum, which suits an environment that is created and destroyed repeatedly. Raise it for anything long-lived."
  type        = number
  default     = 7

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "key_user_arns" {
  description = "IAM principal ARNs allowed to encrypt and decrypt with this key. These go in the key policy; the principals still need matching kms actions in their own policies."
  type        = list(string)
  default     = []
}

variable "service_principals" {
  description = "AWS service principals allowed to use this key, for example s3.amazonaws.com"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates, merged with its own Name tag. A module cannot use the provider's default_tags, so tagging is explicit."
  type        = map(string)
  default     = {}
}
