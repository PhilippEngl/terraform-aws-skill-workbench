variable "aws_region" {
  description = "Region every resource is created in. Must be one where AgentCore and the model you name are both available."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every resource name"
  type        = string
  default     = "demo"
}

# --- Placeholders. Replace all three. -----------------------------------------

variable "vpc_id" {
  description = "Existing VPC to create the endpoints in and deploy into"
  type        = string
  default     = "vpc-0123456789abcdef0"
}

variable "private_subnet_ids" {
  description = "Private subnets with a NAT route. Each interface endpoint gets an ENI in every subnet named here, so this list drives the endpoint cost as well as the workload placement."
  type        = list(string)
  default = [
    "subnet-0123456789abcdef0",
    "subnet-0123456789abcdef1",
  ]
}

variable "private_route_table_ids" {
  description = "Route tables the S3 gateway endpoint is associated with. Usually one per availability zone. An unassociated gateway endpoint routes nothing, so the module rejects an empty list when create_s3_gateway_endpoint is true."
  type        = list(string)
  default = [
    "rtb-0123456789abcdef0",
    "rtb-0123456789abcdef1",
  ]
}

variable "agent_model_id" {
  description = "Model or inference profile the harness is configured with. The geo prefix must match your region's geography."
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-6"
}
