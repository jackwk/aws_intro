provider "aws" {
  region = "eu-central-1"
}

variable "s3_json_bucket" {
  description = "The name of the S3 bucket for storing JSON files"
  type        = string
  default     = "opensky-flights-json-bucket"
}

variable "lambda_code_s3_bucket" {
  description = "The S3 bucket where the Lambda function code is stored"
  type        = string
  default     = "lambda-code-bucket-for-tests"
}

variable "lambda_code_s3_key" {
  description = "The S3 key (file name) of the Lambda function code"
  type        = string
  default     = "function.zip"
}

# S3 Bucket for JSON files
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = var.s3_json_bucket
}

resource "aws_s3_bucket_versioning" "lambda_bucket_versioning" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ],
        Effect = "Allow",
        Resource = [
          "${aws_s3_bucket.lambda_bucket.arn}/*"
        ],
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
    ],
  })
}

# Lambda Function
resource "aws_lambda_function" "opensky_lambda" {
  function_name = "OpenSkyLambda"

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  role = aws_iam_role.lambda_role.arn

  s3_bucket = var.lambda_code_s3_bucket
  s3_key    = var.lambda_code_s3_key

  timeout = 15

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.lambda_bucket.bucket
    }
  }
}

# CloudWatch Event Rule
resource "aws_cloudwatch_event_rule" "lambda_every_5_minutes" {
  name                = "every-5-minutes"
  description         = "Trigger every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "trigger_lambda" {
  rule      = aws_cloudwatch_event_rule.lambda_every_5_minutes.name
  target_id = "OpenSkyLambdaTarget"
  arn       = aws_lambda_function.opensky_lambda.arn
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.opensky_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_every_5_minutes.arn
}
