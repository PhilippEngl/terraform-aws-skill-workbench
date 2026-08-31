# --- Naming and tagging -------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for every resource name this module creates. Names are derived as <name_prefix>-skill-workbench-<role>."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,20}$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter, contain only lowercase letters, digits and dashes, and be 21 characters or fewer so the derived harness name stays inside AgentCore's 40-character limit."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource. Merged with a Name tag the module sets itself, which takes precedence."
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC the harness ENIs and the proxy Lambda are placed in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets with a NAT route. Public subnets do not work: no public IP is assigned to a harness ENI, so there is no egress path and sessions fail on image pull."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must name at least one subnet."
  }
}

variable "vpc_endpoints_to_create" {
  description = "Interface endpoints to create in the VPC. Defaults to none, because in a shared VPC these usually already exist and only one endpoint per service per VPC may have private DNS enabled. Read it as \"create the ones I do not already have\"."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for service in var.vpc_endpoints_to_create :
      contains(["ecr.api", "ecr.dkr", "logs", "kms", "bedrock-agentcore"], service)
    ])
    error_message = "vpc_endpoints_to_create accepts only ecr.api, ecr.dkr, logs, kms and bedrock-agentcore. Other services are not required by this module; create them in your own configuration."
  }
}

variable "create_s3_gateway_endpoint" {
  description = "Whether to create the S3 gateway endpoint. Skills are fetched from S3 by both the harness and the proxy, so a route to S3 is required — but a gateway endpoint is VPC-wide and route-table-scoped, so creating one in a shared VPC affects workloads this module knows nothing about."
  type        = bool
  default     = false
}

variable "private_route_table_ids" {
  description = "Route tables the S3 gateway endpoint is associated with. Required when create_s3_gateway_endpoint is true, ignored otherwise. A gateway endpoint with no association routes nothing."
  type        = list(string)
  default     = []
}

variable "log_level" {
  description = "Log level for the proxy Lambda, read by the Powertools logger as POWERTOOLS_LOG_LEVEL. Set to DEBUG when diagnosing an invocation; the handler logs the full incoming event at INFO regardless, which includes the developer's prompt and any SKILL.md body they saved."
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "log_level must be one of DEBUG, INFO, WARNING, ERROR or CRITICAL."
  }
}

# --- Agent --------------------------------------------------------------------

variable "agent_model_id" {
  description = "Bedrock model or inference profile ID the harness is configured with. Required, because no single model ID is available in every region: a geo prefix such as us. or eu. selects a cross-region inference profile and must match the geography of the region you are deploying into."
  type        = string
}

variable "additional_agent_model_ids" {
  description = "Further models a caller may name per invocation. The frontend offers a model picker, and a per-invocation model replaces the configured one rather than supplementing it, so any model offered in the picker needs permission here or overriding requests fail with AccessDenied while the default model succeeds."
  type        = list(string)
  default     = []
}

variable "system_prompt" {
  description = "System prompt for the workbench agent. Deliberately thin: the point of the module is that behaviour comes from Skills, not from this."
  type        = string
  default     = <<-EOT
    You are a skill-testing assistant running inside a developer workbench.

    Your behaviour is defined almost entirely by the Skills loaded into this session,
    not by this prompt. Read the skills available to you before answering, follow
    whichever one matches the request, and say plainly when none of them applies
    rather than improvising.

    When asked what you can do, list the skills you actually loaded and the tools you
    can actually call. Do not describe capabilities you cannot verify.
  EOT
}

variable "allowed_tools" {
  description = "Tool patterns the harness may select. shell is deliberately excluded: the workbench exists to exercise Skills, and a skill that can shell out can read the shared prefix and exfiltrate it. Set to null to allow every tool. A name that matches nothing leaves the model with no tools and no error, so verify against a deployed harness before changing it."
  type        = list(string)
  default     = ["@builtin/file_operations", "browser"]
}

variable "enable_browser_tool" {
  description = "Whether to attach the managed AgentCore browser tool. It is the one tool a skill can usefully drive without shell access."
  type        = bool
  default     = true
}

variable "memory_strategies" {
  description = "Long-term memory strategies for the managed memory the harness creates. Memory is scoped by actorId rather than by session, so a conversation survives the session rotation the frontend performs to reload skills."
  type        = list(string)
  default     = ["SEMANTIC", "SUMMARIZATION", "USER_PREFERENCE"]
}

variable "memory_event_expiry_days" {
  description = "How long conversation events are retained, in days. A count of days, not an ISO-8601 duration."
  type        = number
  default     = 30
}

variable "max_iterations" {
  description = "Reasoning and action cycles per invocation. The service default is 75."
  type        = number
  default     = 15
}

variable "agent_max_tokens" {
  description = "Output token budget for one whole invocation, enforced by the harness. Null leaves it unlimited. A cost control in the same family as max_iterations and timeout_seconds."
  type        = number
  default     = null

  validation {
    condition     = var.agent_max_tokens == null || var.agent_max_tokens > 0
    error_message = "agent_max_tokens must be greater than zero, or null for no limit."
  }
}

variable "agent_model_max_tokens" {
  description = "Max tokens passed to the model for a single request. Null uses the model's default. Distinct from agent_max_tokens, which bounds the whole invocation."
  type        = number
  default     = null

  validation {
    condition     = var.agent_model_max_tokens == null || var.agent_model_max_tokens > 0
    error_message = "agent_model_max_tokens must be greater than zero, or null for the model default."
  }
}

variable "agent_model_temperature" {
  description = "Sampling temperature passed to the model. Set 0 for the most repeatable output, which is what you want when comparing two runs of the same skill. Null uses the model's default."
  type        = number
  default     = null

  validation {
    condition     = var.agent_model_temperature == null || (var.agent_model_temperature >= 0 && var.agent_model_temperature <= 1)
    error_message = "agent_model_temperature must be between 0 and 1 inclusive, or null."
  }
}

variable "agent_model_top_p" {
  description = "Nucleus sampling parameter passed to the model. Setting this and temperature together is usually a mistake; pick one. Null uses the model's default."
  type        = number
  default     = null

  validation {
    condition     = var.agent_model_top_p == null || (var.agent_model_top_p > 0 && var.agent_model_top_p <= 1)
    error_message = "agent_model_top_p must be greater than 0 and at most 1, or null."
  }
}

variable "timeout_seconds" {
  description = "Wall-clock timeout for one harness invocation. The proxy Lambda's timeout is derived from this as timeout_seconds + 30, because the proxy holds the event stream open for the whole turn."
  type        = number
  default     = 300

  validation {
    condition     = var.timeout_seconds > 0 && var.timeout_seconds <= 870
    error_message = "timeout_seconds must be between 1 and 870, because the proxy Lambda's timeout is timeout_seconds + 30 and Lambda's maximum is 900."
  }
}

# --- Frontend -----------------------------------------------------------------

variable "frontend_dev_origins" {
  description = "Extra CORS origins allowed to read the skill bucket. Without the Vite dev server here, reading a skill from a locally served frontend fails on CORS."
  type        = list(string)
  default     = ["http://localhost:5173"]
}

# --- Logging ------------------------------------------------------------------

variable "access_log_bucket_name" {
  description = "Existing bucket to deliver the skill bucket's S3 server access logs to. Null, the default, disables access logging: the module does not create a log destination. Supply one when you want to detect access that did not come through the proxy — in-band requests are already logged by the proxy Lambda, which is the only S3 caller. The bucket must be in this region and account, must not use SSE-KMS, and its policy must already allow s3:PutObject for logging.s3.amazonaws.com with your account as aws:SourceAccount. All three are AWS constraints on log delivery, and breaking any of them fails by silently never delivering a log."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the proxy Lambda's CloudWatch Logs group. Exposed because an organisation with a retention policy has to be able to set it, and because a log group with no retention keeps everything forever and bills for it forever. The module always owns the log group rather than letting Lambda auto-create one, so this is honoured and a destroy leaves nothing behind."
  type        = number
  default     = 14

  validation {
    condition = contains(
      [1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be one of the retention periods CloudWatch Logs accepts: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653."
  }
}
