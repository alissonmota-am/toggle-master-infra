################################################################################
# SQS Queue
################################################################################
resource "aws_sqs_queue" "this" {
  name                       = var.queue_name
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 dias

  tags = {
    Name = var.queue_name
  }
}

################################################################################
# DynamoDB Table
################################################################################
resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = {
    Name = var.table_name
  }
}
