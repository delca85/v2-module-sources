terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "aws_iam_role" "role" {
  count       = var.iam_role_arn == null ? 1 : 0
  name_prefix = "lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  tags = var.additional_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = var.iam_role_arn == null ? aws_iam_role.role[0].name : var.iam_role_arn
}

resource "aws_iam_role_policy" "s3" {
  count = var.iam_role_arn == null ? 1 : 0
  role  = aws_iam_role.role[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket}/${var.s3_key}"
      }
    ]
  })
}

# Attach additional managed policies to the Lambda role
resource "aws_iam_role_policy_attachment" "additional_managed_policies" {
  for_each = var.iam_role_arn == null ? toset(var.additional_managed_policy_arns) : []

  role       = aws_iam_role.role[0].name
  policy_arn = each.value
}

# Attach additional inline policies to the Lambda role
resource "aws_iam_role_policy" "additional_inline_policies" {
  for_each = var.iam_role_arn == null ? var.additional_inline_policies : {}

  role   = aws_iam_role.role[0].id
  name   = each.key
  policy = each.value
}

resource "random_id" "entropy" {
  byte_length = 4
}

# locals {
#   has_service = try(length(var.service.ports), 0) > 0
# }

resource "aws_lambda_function" "function" {
  function_name = "${var.name_prefix}-${random_id.entropy.hex}"
  role          = var.iam_role_arn != null ? var.iam_role_arn : aws_iam_role.role[0].arn

  package_type = "Zip"
  s3_bucket    = var.s3_bucket
  s3_key       = var.s3_key

  handler = var.handler
  runtime = var.runtime

  environment {
    variables = var.environment_variables
  }

  architectures = var.architectures

  timeout     = var.timeout_in_seconds
  memory_size = var.memory_size

  tags = var.additional_tags
}

# Lambda Function URL - Creates an HTTPS endpoint for the Lambda
resource "aws_lambda_function_url" "function_url" {
  count = var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.function.function_name
  authorization_type = var.function_url_auth_type

  dynamic "cors" {
    for_each = var.function_url_cors != null ? [var.function_url_cors] : []
    content {
      allow_credentials = cors.value.allow_credentials
      allow_origins     = cors.value.allow_origins
      allow_methods     = cors.value.allow_methods
      allow_headers     = cors.value.allow_headers
      expose_headers    = cors.value.expose_headers
      max_age           = cors.value.max_age
    }
  }
}
