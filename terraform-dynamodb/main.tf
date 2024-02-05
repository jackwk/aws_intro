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
