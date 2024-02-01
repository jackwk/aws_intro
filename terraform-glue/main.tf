provider "aws" {
  region = "eu-central-1"
}

resource "aws_iam_role" "glue_role" {
  name = "glue_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "glue.amazonaws.com"
        },
      },
    ],
  })
}

resource "aws_iam_policy_attachment" "glue_s3_read_only" {
  name       = "glue_s3_read_only"
  roles      = [aws_iam_role.glue_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_dynamodb_table" "opensky_table" {
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
    type = "S" # Assuming time_position will be stored as a string in ISO 8601 format
  }

  # No need to define other attributes here as they are not part of the primary key or indexes

  tags = {
    Purpose = "Store OpenSky API Data"
  }
}

resource "aws_glue_catalog_database" "glue_database" {
  name = "opensky-glue-database"
}

resource "aws_glue_catalog_table" "glue_catalog_table" {
  name          = "opensky-glue-catalog-table"
  database_name = aws_glue_catalog_database.glue_database.name

  storage_descriptor {
    location      = "s3://lambda-code-bucket-for-tests/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    columns {
      name = "example_column"
      type = "string"
    }

    # Add additional columns as needed
  }

  table_type = "EXTERNAL_TABLE"
}

resource "aws_glue_job" "glue_job" {
  name     = "glue-job"
  role_arn = aws_iam_role.glue_role.arn

  command {
    script_location = "s3://lambda-code-bucket-for-tests/glue-script.py"
    name            = "glueetl"
  }

  default_arguments = {
    "--job-bookmark-option" = "job-bookmark-enable"
    "--TempDir"             = "s3://lambda-code-bucket-for-tests/temp-dir"
  }

  max_capacity = 2.0
}

resource "aws_cloudwatch_log_group" "glue_log_group" {
  name = "/aws-glue/jobs"
}

resource "aws_glue_trigger" "glue_trigger" {
  name     = "glue-trigger"
  type     = "SCHEDULED"
  schedule = "cron(0 12 * * ? *)"  # This will run the job daily at 12:00 PM UTC

  actions {
    job_name = aws_glue_job.glue_job.name
  }
}

# Add any additional configurations or resources as necessary
