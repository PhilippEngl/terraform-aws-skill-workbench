variable "aws_region" {
  description = "Region every resource is created in. Must be one where AgentCore and the model you name are both available."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name. Bounded at 21 characters by the module, because the derived harness name has a 40-character limit."
  type        = string
  default     = "demo"
}

# --- Placeholders. Replace all three. -----------------------------------------
# Deliberately given defaults so that `terraform validate` runs on a fresh clone with no
# tfvars file. They are not real identifiers, so an apply fails immediately rather than
# creating anything in the wrong place.

variable "vpc_id" {
  description = "Existing VPC to deploy into"
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "private_subnet_ids" {
  description = "Private subnets with a NAT route, for the harness ENIs and the proxy Lambda. Two or more in different availability zones is the sensible minimum."
  type        = list(string)
  default = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
  ]
}

# --- Models -------------------------------------------------------------------

variable "agent_model_id" {
  description = "Model or inference profile the harness is configured with. The us. prefix is a cross-region inference profile; use the prefix matching your region's geography."
  type        = string
  default     = "us.anthropic.claude-sonnet-4-6"
}

variable "additional_agent_model_ids" {
  description = "Further models the frontend's picker offers. Each needs the execution role's permission, which the module grants from this list."
  type        = list(string)
  default     = ["us.anthropic.claude-haiku-4-5"]
}
