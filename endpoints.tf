# VPC endpoints, opt in rather than on by default. Two properties this module cannot
# detect, both of which the README repeats:
#
#   1. Only one interface endpoint per service per VPC may have private DNS enabled.
#      So `vpc_endpoints_to_create` means "create the ones I do not already have", and
#      naming a service that already has an endpoint fails at apply.
#   2. Destroying this module destroys the endpoints it created. In a shared VPC those
#      may by then be carrying traffic for workloads it knows nothing about.

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "endpoints" {
  #checkov:skip=CKV2_AWS_5: "Attached via resource aws_vpc_endpoint.interface, as security_group_ids in endpoints.tf. Both are created together by vpc_endpoints_to_create, so the group never exists unattached."

  count = length(var.vpc_endpoints_to_create) > 0 ? 1 : 0

  name        = "${local.name}-endpoints-sg"
  description = "Interface VPC endpoint ENIs for the ${local.name} workbench"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  tags = merge(var.tags, {
    Name = "${local.name}-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.vpc_endpoints_to_create)

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type = "Interface"

  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${local.name}-${each.value}-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_s3_gateway_endpoint ? 1 : 0

  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  tags = merge(var.tags, {
    Name = "${local.name}-s3-endpoint"
  })

  lifecycle {
    precondition {
      condition     = length(var.private_route_table_ids) > 0
      error_message = "create_s3_gateway_endpoint is true but private_route_table_ids is empty. A gateway endpoint with no route table association routes nothing, and the harness would still fail to reach S3."
    }
  }
}

resource "aws_vpc_endpoint_route_table_association" "s3" {
  count = var.create_s3_gateway_endpoint ? length(var.private_route_table_ids) : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id  = var.private_route_table_ids[count.index]
}
