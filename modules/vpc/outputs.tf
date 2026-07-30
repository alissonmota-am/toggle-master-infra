output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_id" {
  description = "ID do NAT Gateway"
  value       = aws_nat_gateway.this.id
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway"
  value       = aws_internet_gateway.this.id
}
