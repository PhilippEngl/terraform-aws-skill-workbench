variable "aws_region" {
  description = "Region every resource is created in. Must be one where AgentCore and the model you name are both available."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every resource name"
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC this example creates. A /16 leaves room for the /24 subnets it carves out and for more later."
  type        = string
  default     = "10.0.0.0/16"
}

variable "agent_model_id" {
  description = "Model or inference profile the harness is configured with. The geo prefix must match your region's geography."
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-6"
}
