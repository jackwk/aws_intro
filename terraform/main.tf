provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "my-bucket-for-lambda-files"
}

resource "aws_s3_bucket_versioning" "lambda_bucket_versioning" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

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

resource "aws_iam_policy" "lambda_s3_policy" {
  name = "lambda_s3_policy"
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
    ],
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_policy.arn
}

resource "aws_lambda_function" "opensky_lambda" {
  function_name = "OpenSkyLambda"

  // Replace with the appropriate runtime and handler
  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  role = aws_iam_role.lambda_role.arn

  // Replace with the actual path to your Lambda deployment package
  s3_bucket        = "lambda-code-bucket-for-tests"
  s3_key           = "function.zip"

  timeout = 15

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.lambda_bucket.bucket
    }
  }
}
