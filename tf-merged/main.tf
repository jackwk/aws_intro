# Basic setup & variables

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "current" {}

variable "s3_json_bucket" {
  description = "The name of the S3 bucket for storing JSON files"
  type        = string
  default     = "opensky-flights-json-bucket"
}

variable "s3_cloudtrail_bucket" {
  description = "The name of the S3 bucket for CloudTrail logs"
  type        = string
  default     = "cloudtrail-s3-logs-for-eb"
}

variable "s3_code_bucket" {
  description = "The S3 bucket where the Lambda function code is stored"
  type        = string
  default     = "lambda-code-bucket-for-tests"
}

variable "s3_bucket_url" {
  description = "The URL of the S3 bucket used by the Glue job"
  default     = "s3://lambda-code-bucket-for-tests/"
}

variable "lambda_code_s3_key" {
  description = "The S3 key (file name) of the Lambda function code"
  type        = string
  default     = "function.zip"
}

# S3 Buckets & policies
resource "aws_s3_bucket" "lambda_bucket" {
  bucket = var.s3_json_bucket
  force_destroy = true
}

resource "aws_s3_bucket" "cloudtrail_logs_bucket" {
  bucket = var.s3_cloudtrail_bucket
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "lambda_bucket_versioning" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck",
        Effect    = "Allow",
        Principal = {"Service": "cloudtrail.amazonaws.com"},
        Action    = "s3:GetBucketAcl",
        Resource  = "arn:aws:s3:::${var.s3_cloudtrail_bucket}"
      },
      {
        Sid       = "AWSCloudTrailWrite",
        Effect    = "Allow",
        Principal = {"Service": "cloudtrail.amazonaws.com"},
        Action    = "s3:PutObject",
        Resource  = "arn:aws:s3:::${var.s3_cloudtrail_bucket}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {"s3:x-amz-acl": "bucket-owner-full-control"}
        }
      }
    ]
  })
}

# Cloudtrail

resource "aws_cloudtrail" "s3_json_bucket_trail" {
  name                          = "s3_json_bucket_trail"
  s3_bucket_name                = var.s3_cloudtrail_bucket
  include_global_service_events = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.s3_json_bucket}/"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs_policy
  ]
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

# IAM Rule for EventBridge

resource "aws_iam_role" "eventbridge_glue_role" {
  name = "eventbridge_glue_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "eventbridge_glue_policy" {
  name   = "eventbridge_glue_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartWorkflowRun",
          "glue:notifyEvent",
        ],
        Resource = [
          aws_glue_workflow.opensky_workflow.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_glue_policy_attachment" {
  role       = aws_iam_role.eventbridge_glue_role.name
  policy_arn = aws_iam_policy.eventbridge_glue_policy.arn
}

# Lambda Function
resource "aws_lambda_function" "opensky_lambda" {
  function_name = "OpenSkyLambda"

  runtime = "python3.12"
  handler = "lambda_function.lambda_handler"

  role = aws_iam_role.lambda_role.arn

  s3_bucket = var.s3_code_bucket
  s3_key    = var.lambda_code_s3_key

  timeout = 30

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.lambda_bucket.bucket
    }
  }
}

# CloudWatch Event Rule + EventBridge Lambda Rule
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

resource "aws_glue_job" "opensky-glue-job" {
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

resource "aws_glue_workflow" "opensky_workflow" {
  name = "opensky-workflow"
}

resource "aws_glue_trigger" "opensky_trigger" {
  name          = "opensky-trigger"
  workflow_name = aws_glue_workflow.opensky_workflow.name
  type          = "EVENT"

  actions {
    job_name = aws_glue_job.opensky-glue-job.name
  }
}

# EventBridge for Glue

resource "aws_cloudwatch_event_rule" "s3_write_event_rule" {
  name        = "s3-write-event-rule"
  description = "Trigger on S3 write events"

  event_pattern = jsonencode({
  "detail-type": ["AWS API Call via CloudTrail"],
  "source": ["aws.s3"],
  "detail": {
    "eventSource": ["s3.amazonaws.com"],
    "requestParameters": {
      "bucketName": [var.s3_json_bucket]
    },
    "eventName": ["PutObject"]
  }
})
}

resource "aws_cloudwatch_event_target" "glue_workflow_target" {
  rule      = aws_cloudwatch_event_rule.s3_write_event_rule.name
  target_id = "TriggerGlueWorkflow"
  arn       = aws_glue_workflow.opensky_workflow.arn
  role_arn  = aws_iam_role.eventbridge_glue_role.arn
}
