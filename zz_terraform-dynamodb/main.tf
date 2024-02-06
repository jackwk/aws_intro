provider "aws" {
  region = "eu-central-1"
}

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
  description = "Policy for Glue Job to access S3 and DynamoDB"

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
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_dynamodb_attach" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = aws_iam_policy.glue_s3_dynamodb_policy.arn
}

resource "aws_glue_job" "example_glue_job" {
  name     = "example-glue-job"
  role_arn = aws_iam_role.glue_job_role.arn

  command {
    script_location = "s3://lambda-code-bucket-for-tests/glue-script.py"
    name            = "glueetl"
    python_version  = "3" # Make sure this matches the version used in your script
  }

  glue_version = "2.0" # Or the appropriate version
  max_capacity = 2.0   # Adjust this based on your job's needs

  default_arguments = {
    "--TempDir" = "s3://lambda-code-bucket-for-tests/temp-dir"
  }

  max_retries = 0
  timeout     = 60 # Set this according to how long your job might need to run
}
