################################################################################
# Pacote da Lambda
# O .zip e gerado durante o plan em build/. Como o plan e o apply rodam em jobs
# separados no GitHub Actions, o workflow inclui esse arquivo no artefato do plan.
################################################################################
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/src/handler.py"
  output_path = "${path.module}/build/self-healing.zip"
}

################################################################################
# Role de execucao da Lambda (so escreve logs no CloudWatch)
################################################################################
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

################################################################################
# Logs
################################################################################
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}

################################################################################
# Funcao Lambda
################################################################################
resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = "Recebe o webhook do Alertmanager e dispara o workflow de self-healing no GitHub Actions"
  role          = aws_iam_role.this.arn
  runtime       = "python3.12"
  handler       = "handler.handler"
  timeout       = 15
  memory_size   = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      WEBHOOK_TOKEN    = var.webhook_token
      GITHUB_TOKEN     = var.github_token
      GITHUB_REPO      = var.github_repo
      GITHUB_WORKFLOW  = var.github_workflow
      GITHUB_REF_NAME  = var.github_ref
      ALLOWED_SERVICES = join(",", var.allowed_services)
    }
  }

  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy_attachment.logs]
}

################################################################################
# Function URL (endpoint HTTPS publico)
# A autorizacao e feita no codigo, pelo token compartilhado (AuthType NONE).
# Desde out/2025 uma URL publica exige as permissoes lambda:InvokeFunctionUrl e
# lambda:InvokeFunction (esta com InvokedViaFunctionUrl). A partir do provider
# AWS 6.28, este recurso cria ambas automaticamente quando authorization_type = NONE.
################################################################################
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
}
