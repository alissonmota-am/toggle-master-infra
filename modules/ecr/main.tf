################################################################################
# ECR Repositories
################################################################################
resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = {
    Name    = "${var.project_name}/${each.value}"
    Service = each.value
  }
}
