output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used, in subnet order."
  value       = var.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs, one per AZ (same order as azs)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs, one per AZ (same order as azs). Use these for EKS nodes and the control plane ENIs."
  value       = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  description = "CIDRs of the public subnets."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "CIDRs of the private subnets."
  value       = aws_subnet.private[*].cidr_block
}

output "private_route_table_ids" {
  description = "Private route table IDs (one per AZ), e.g. for additional gateway endpoints."
  value       = aws_route_table.private[*].id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs (empty when nat_gateway_mode = none)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Egress public IPs of the NAT gateways - allow-list these at third parties."
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs (null if disabled)."
  value       = one(aws_cloudwatch_log_group.flow_logs[*].name)
}
