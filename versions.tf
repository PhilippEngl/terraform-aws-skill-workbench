terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # AgentCore harness attributes landed in 6.61.0, so there is no headroom below
      # this floor. Bounded below 7.0 because a major provider release may rename or
      # retype the arguments used here.
      version = ">= 6.61, < 7.0"
    }
  }
}
