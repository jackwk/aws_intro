#initial configuration

provider "aws" {
  region = "eu-central-1"
}

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
          "arn:aws:s3:::lambda-code-bucket-for-tests"
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
