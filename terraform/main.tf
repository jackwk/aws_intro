provider "aws" {
  region = "eu-central-1" # You can change this to your desired AWS region
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "bucket-z-terraforma-1235" # Bucket names must be globally unique
  acl    = "private" # Defines the access control level

  tags = {
    Name        = "Source"
    Environment = "TF"
  }
}
