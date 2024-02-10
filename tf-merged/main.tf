provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "opensky-flights-json-bucket"
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

resource "aws_lambda_function" "opensky_lambda" {
  function_name = "OpenSkyLambda"

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

#initial configuration

variable "s3_bucket_url" {
  description = "The URL of the S3 bucket used by the Glue job"
  default     = "s3://lambda-code-bucket-for-tests/"
}

#DynamoDB

resource "aws_dynamodb_table" "opensky_data" {
  name           = "OpenSkyData"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "icao24"
  range_key      = "time_position"

  attribute {
    name = "icao24"
    type = "S"
  }

  attribute {
    name = "time_position"
    type = "N"
  }

  tags = {
    Purpose = "Store OpenSky API Data"
  }
}

#IAM Stuff

resource "aws_iam_role" "glue_job_role" {
  name = "glue-job-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com",
        },
      },
    ],
  })
}

resource "aws_iam_policy" "glue_s3_dynamodb_policy" {
  name        = "glue_s3_dynamodb_policy"
  description = "Policy for Glue Job to access S3, DynamoDB, and full CloudWatch Logs permissions"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:dynamodb:*:*:table/OpenSkyData"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Effect   = "Allow",
        Resource = [
          "arn:aws:s3:::lambda-code-bucket-for-tests/*",
          "arn:aws:s3:::lambda-code-bucket-for-tests",
          "arn:aws:s3:::opensky-flights-json-bucket/*",
		  "arn:aws:s3:::opensky-flights-json-bucket"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Effect = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "glue_s3_dynamodb_attach" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_s3_dynamodb_policy.arn
}

#CloudWatch stuff
resource "aws_cloudwatch_log_group" "glue_jobs_output" {
  name = "/aws-glue/jobs/output"
}

resource "aws_cloudwatch_log_group" "glue_jobs_logs_v2" {
  name = "/aws-glue/jobs/logs-v2"
}

resource "aws_cloudwatch_log_group" "glue_jobs_error" {
  name = "/aws-glue/jobs/error"
}

resource "aws_cloudwatch_log_group" "glue_jobs" {
  name = "/aws-glue/jobs"
}

#Glue job

resource "aws_glue_job" "example_glue_job" {
  name     = "opensky-glue-job"
  role_arn = aws_iam_role.glue_job_role.arn

  command {
    script_location = "${var.s3_bucket_url}glue-script.py"
    name            = "glueetl"
    python_version  = "3" 
  }

  glue_version = "4.0" 
  max_capacity = 2.0   

  default_arguments = {
    "--TempDir" = "${var.s3_bucket_url}temp-dir"
  }

  max_retries = 0
  timeout     = 60 
}
