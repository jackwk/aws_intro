#init

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  required_version = ">= 0.12"
}

provider "aws" {
  region = "eu-central-1" # Specify your AWS region
}

variable "S3BucketName" {
  description = "This is used to store data, CloudTrail logs, job scripts, and any temporary files generated during the AWS Glue ETL job run."
  type        = string
  default     = "s3-bucket-for-eb-and-glue"
}

variable "WorkflowName" {
  description = "A data processing pipeline that is comprised of a crawler, jobs, and triggers. This workflow converts uploaded data files into Apache Parquet format."
  type        = string
  default     = "s3trigger_data_conversion_workflow"
}

variable "DatabaseName" {
  description = "The AWS Glue Data Catalog database that is used to hold the tables created in this walkthrough."
  type        = string
  default     = "event_driven_workflow_tutorial"
}

variable "TableName" {
  description = "The Data Catalog table representing the Parquet files being converted by the workflow."
  type        = string
  default     = "products"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "s3_bucket" {
  bucket = var.S3BucketName
}

resource "aws_s3_bucket_public_access_block" "s3_public_access_block" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_policy" "s3_bucket_policy" {
  bucket = aws_s3_bucket.s3_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AWSCloudTrailWrite",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:PutObject",
        Resource = "${aws_s3_bucket.s3_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid = "AWSCloudTrailRead",
        Effect = "Allow",
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        },
        Action = "s3:GetBucketAcl",
        Resource = aws_s3_bucket.s3_bucket.arn
      }
    ]
  })
}


resource "aws_cloudtrail" "trail" {
  name                          = "s3-event-trail-${terraform.workspace}"
  s3_bucket_name                = aws_s3_bucket.s3_bucket.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = false

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = false
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.s3_bucket.arn}/data/products_raw/"]
    }
  }
}

resource "aws_cloudwatch_event_rule" "s3_event_rule" {
  name        = "s3-file-upload-trigger-rule"
  description = "Triggers Glue workflow on S3 PutObject event"

  event_pattern = jsonencode({
    "source" : ["aws.s3"],
    "detail-type" : ["AWS API Call via CloudTrail"],
    "detail" : {
      "eventSource" : ["s3.amazonaws.com"],
      "eventName" : ["PutObject"],
      "requestParameters" : {
        "bucketName" : [var.S3BucketName],
        "key" : [{
          "prefix" : "data/products_raw/"
        }]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "glue_workflow_target" {
  rule      = aws_cloudwatch_event_rule.s3_event_rule.name
  target_id = "TargetForGlueWorkflow"

  arn = "arn:aws:glue:eu-central-1:656122958899:workflow/wf-glue"

  role_arn = aws_iam_role.eventbridge_glue_role.arn
}

resource "aws_iam_role" "eventbridge_glue_role" {
  name = "EventBridgeGlueExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_invoke_policy" {
  name   = "InvokeGlueWorkflowPolicy"
  role   = aws_iam_role.eventbridge_glue_role.id
  policy = data.aws_iam_policy_document.glue_invoke_policy_document.json
}

data "aws_iam_policy_document" "glue_invoke_policy_document" {
  statement {
    actions = ["glue:StartWorkflowRun"]
    resources = ["arn:aws:glue:eu-central-1:656122958899:workflow/wf-glue"]
  }
}
