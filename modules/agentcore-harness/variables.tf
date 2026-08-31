variable "name" {
  description = "Harness name. AgentCore rejects dashes, so derive this from the resource name with replace(..., \"-\", \"_\")."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,39}$", var.name))
    error_message = "Harness name must match ^[a-zA-Z][a-zA-Z0-9_]{0,39}$: start with a letter, then letters, digits and underscores only, 40 characters maximum. Dashes are rejected by the service."
  }
}

variable "model_id" {
  description = "Bedrock model or inference profile ID. A geo prefix such as us. or eu. selects a cross-region inference profile and determines which regions inference may run in, so it must match the geography you intend; a profile carrying the wrong prefix, or none at all, may not resolve in this region. There is deliberately no default, because no single model ID is available in every region."
  type        = string
}

variable "additional_model_ids" {
  description = "Further models the execution role may invoke. Needed when callers pass a per-invocation `model` override, which replaces the configured model rather than supplementing it — so a model named only by the caller still needs permission here."
  type        = list(string)
  default     = []
}

variable "system_prompt" {
  description = "System prompt for the agent"
  type        = string
}

variable "allowed_tools" {
  description = "Tool patterns the model may select. Leave null for all. Note this does NOT gate InvokeAgentRuntimeCommand, which executes shell commands as root without passing through the model — withhold that IAM action instead."
  type        = list(string)
  default     = null
}

variable "max_iterations" {
  description = "Reasoning and action cycles per invocation. Service default is 75."
  type        = number
  default     = 10
}

variable "timeout_seconds" {
  description = "Wall-clock timeout for one invocation. Service default is 3600."
  type        = number
  default     = 300
}

variable "max_tokens" {
  description = "Output token budget per invocation. Null for no limit."
  type        = number
  default     = null
}

variable "model_max_tokens" {
  description = "Per-request max tokens passed to the model"
  type        = number
  default     = null
}

variable "model_temperature" {
  description = "Sampling temperature passed to the model"
  type        = number
  default     = null
}

variable "model_top_p" {
  description = "Nucleus sampling parameter passed to the model"
  type        = number
  default     = null
}

variable "environment_variables" {
  description = "Environment variables available inside the harness microVM"
  type        = map(string)
  default     = null
}

variable "memory_event_expiry_duration" {
  description = "How long conversation events are retained, in days. The service default for managed memory is 30. Note this is a number, not an ISO-8601 duration."
  type        = number
  default     = 30
}

variable "memory_encryption_key_arn" {
  description = "Customer managed KMS key for memory at rest. Null uses the service key."
  type        = string
  default     = null
}

variable "memory_strategies" {
  description = "Long-term memory strategies. Documented values are SEMANTIC, SUMMARIZATION, USER_PREFERENCE and EPISODIC."
  type        = list(string)
  default     = null
}

variable "network_mode" {
  description = "PUBLIC or VPC. VPC is egress-only: it gives no inbound endpoint, so nothing can target the harness from a load balancer. It also requires interface endpoints for ecr.dkr, ecr.api and logs plus an S3 gateway endpoint, or sessions fail on image pull timeout."
  type        = string
  default     = "VPC"

  validation {
    condition     = contains(["PUBLIC", "VPC"], var.network_mode)
    error_message = "network_mode must be PUBLIC or VPC."
  }
}

variable "subnet_ids" {
  description = "Private subnets for the harness ENIs when network_mode is VPC. Public subnets do not work: no public IP is assigned, so there is no egress path."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security groups for the harness ENIs when network_mode is VPC. Service-owned ENIs can hold these for up to 8 hours after deletion, so the stack owning them owns that teardown delay."
  type        = list(string)
  default     = []
}

variable "browser_tool_name" {
  description = "Name to attach the managed AgentCore browser tool under. Null attaches no browser. This name is what allowed_tools must match — a mismatch leaves the model with no tools and no error."
  type        = string
  default     = null
}

variable "additional_policy_json" {
  description = "Extra IAM policy documents for the execution role, as rendered JSON. Use this for bucket access needed by InvokeAgentRuntimeCommand post-processing."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates, merged with its own Name tag. A module cannot use the provider's default_tags, so tagging is explicit."
  type        = map(string)
  default     = {}
}
