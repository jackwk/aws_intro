provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "cloutrail-s3-logs-for-eb"
}

resource "aws_s3_bucket_policy" "cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = {"Service": "cloudtrail.amazonaws.com"}
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::cloutrail-s3-logs-for-eb"
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = {"Service": "cloudtrail.amazonaws.com"}
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::cloutrail-s3-logs-for-eb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {"s3:x-amz-acl": "bucket-owner-full-control"}
        }
      }
    ]
  })
}


data "aws_caller_identity" "current" {}

resource "aws_cloudtrail" "example" {
  name                          = "example"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.bucket
  include_global_service_events = true

  event_selector {
    read_write_type           = "WriteOnly"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::opensky-flights-json-bucket/"]
    }
  }
}
