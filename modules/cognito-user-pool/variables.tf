variable "name" {
  description = "Name for the user pool, client, identity pool and authenticated role"
  type        = string
}

variable "self_signup_enabled" {
  description = "Whether anyone may register themselves. False means administrators create users, which is the right default unless you intend the workbench to be publicly registrable."
  type        = bool
  default     = false
}

variable "password_minimum_length" {
  description = "Minimum password length. Lowercase, uppercase, digits and symbols are always required."
  type        = number
  default     = 8
}

variable "authenticated_policy_json" {
  description = "IAM policy documents attached inline to the authenticated role, as rendered JSON. This is exactly what a signed-in browser can do directly, so keep it scoped. In this module it grants lambda:InvokeFunction on the proxy and nothing else."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates, merged with its own Name tag. A module cannot use the provider's default_tags, so tagging is explicit."
  type        = map(string)
  default     = {}
}
