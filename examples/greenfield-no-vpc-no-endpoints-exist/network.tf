# The network this example builds from nothing, so that `terraform apply` in an empty
# account produces a working workbench.
#
# Written as plain resources rather than with a community VPC module on purpose. This is
# documentation as much as it is configuration: the module requires private subnets with
# egress and, if it is to create the S3 gateway endpoint, the route tables to associate it
# with. A VPC module would hide exactly the parts a reader needs to see.
#
# Note what is NOT here: the module still creates no network of its own. Everything below
# belongs to this example, and in a real account it belongs to whoever owns the VPC.

# AZ names are per-account aliases for the underlying zones, so they are resolved rather
# than hardcoded — a hardcoded list breaks silently when the region changes. Zones needing
# opt-in are excluded because a subnet in one fails to create.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 10.0.0.0/24 for the public subnet, then 10.0.10.0/24 upwards for the private ones.
  # The gap is deliberate headroom: more public subnets can be added later without
  # renumbering the private ones, which would replace them and everything attached.
  public_subnet_cidr   = cidrsubnet(var.vpc_cidr, 8, 0)
  private_subnet_cidrs = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both are required for interface VPC endpoints. Private DNS is how an endpoint
  # intercepts the service's public hostname, and without DNS support it cannot.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-skill-workbench"
  }
}

# AWS creates a security group with every VPC and allows all traffic between its members
# plus all egress. Nothing in this example uses it, but it exists, and anything later
# launched into the VPC without naming a group lands in it. Declaring it here with no
# ingress or egress blocks empties it — the group itself cannot be deleted, only emptied.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-skill-workbench-default-do-not-use"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-skill-workbench"
  }
}

# One public subnet, holding nothing but the NAT gateway. No workload belongs here: an
# AgentCore harness ENI is assigned no public IP, so a public subnet leaves it with no
# egress path at all rather than with a slower one.
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.public_subnet_cidr
  availability_zone = local.azs[0]

  # Deliberately not set. The NAT gateway carries its own Elastic IP, and nothing else
  # is placed here, so auto-assigning public addresses would only create surprises.
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-skill-workbench-public"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.name_prefix}-skill-workbench-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-skill-workbench-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# One NAT gateway, not one per availability zone. That is a cost choice for an example and
# the wrong one for production: a single NAT means traffic from the second zone crosses
# zones, and a zone failure takes egress with it. Production wants one per zone, each with
# its own private route table.
#
# NAT is not optional even with every VPC endpoint this module can create. The harness's
# managed browser tool reaches the public web, and the Bedrock model call does not travel
# over any endpoint in the module's allowlist.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.name_prefix}-skill-workbench"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-skill-workbench-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# One private route table shared by both private subnets, because there is one NAT gateway
# for them to point at. This is what gets passed to the module as private_route_table_ids,
# and it is why that input is a list of exactly one element here rather than one per subnet:
# the S3 gateway endpoint is associated with route tables, not with subnets.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-skill-workbench-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Flow logs ---------------------------------------------------------------
# The only thing in this example that bills for volume rather than for time, and the
# reason it is here anyway: a VPC with no flow logs cannot answer the one question worth
# asking after an incident, which is what the harness talked to. The harness reaches the
# public web through the NAT gateway by design — that is what the managed browser tool is
# for — so "what did it reach" is not a question the security groups can answer.
#
# CloudWatch Logs rather than S3 as the destination, because S3 delivery needs a bucket
# and a bucket policy, and this example deliberately does not own a bucket. Retention is
# short: these are for reading in the days after something happened, not for keeping.
resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_158: "CloudWatch Logs encrypts log data at rest with an AWS-owned key already; what a CMK adds is key-level access control and an audit trail on decryption. Providing one means this example creating a KMS key plus a key policy for logs.<region>.amazonaws.com, and what it would protect is network metadata — addresses, ports and byte counts — rather than content."
  #checkov:skip=CKV_AWS_338: "The check asks for a year. These records exist to be read in the days after an incident, they bill for volume, and the module's own proxy log group defaults to 14 days via log_retention_days — a year here would contradict the stance the module takes about its own logs."

  name              = "/aws/vpc/flow-logs/${var.name_prefix}-skill-workbench"
  retention_in_days = 7

  tags = {
    Name = "${var.name_prefix}-skill-workbench-flow-logs"
  }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    # Scoped to this log group and its streams. The delivery service is given no reason to
    # be able to write anywhere else.
    resources = [
      aws_cloudwatch_log_group.flow_logs.arn,
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-skill-workbench-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = {
    Name = "${var.name_prefix}-skill-workbench-flow-logs"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "delivery"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name = "${var.name_prefix}-skill-workbench"
  }
}
