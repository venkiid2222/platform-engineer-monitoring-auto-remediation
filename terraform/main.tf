terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.al2.id
  instance_type = var.instance_type

  tags = {
    Name = "platform-test-ec2"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "platform-test-alerts"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_function"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "platform-test-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "platform-test-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ec2:RebootInstances"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "restart_ec2" {
  function_name = "restart-ec2-from-sumo"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.11"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID   = aws_instance.app.id
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

# -----------------------------
# Lambda Function URL (created, but blocked by account-level policy)
# Kept here for completeness; webhook should use API Gateway URL instead.
# -----------------------------
resource "aws_lambda_function_url" "function_url" {
  function_name      = aws_lambda_function.restart_ec2.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "AllowPublicFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.restart_ec2.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# -----------------------------
# API Gateway HTTP API (use this as the webhook URL)
# -----------------------------
resource "aws_apigatewayv2_api" "http_api" {
  name          = "platform-test-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.restart_ec2.invoke_arn
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.restart_ec2.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

# -----------------------------
# Outputs
# -----------------------------
output "api_gateway_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "sumo_webhook_url" {
  value = aws_lambda_function_url.function_url.function_url
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
