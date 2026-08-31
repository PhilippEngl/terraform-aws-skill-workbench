config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.44.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Naming inside this module is snake_case for identifiers and dashes for the
# resource names it builds from var.name_prefix.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Every module, nested ones included, declares its own required_version and
# required_providers. For a child module that is not redundant with the root's: it is
# what makes the module usable on its own, and what turns "wrong Terraform version" into
# an init-time error rather than a failure somewhere deep inside it.
#
# Note this is separate from lock files, which are deliberately absent here — a module
# must not pin its caller's provider versions, so only the examples commit one.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

# Every variable and output carries a description; the README is generated from them.
rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
