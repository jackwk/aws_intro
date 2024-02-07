import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import explode, col

#This one works with following JSON
#{"time": 1706735499, "states": [
#    ["4b180b", "SWCCAA", 1707122543]
#    ]
#}

import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import explode, col

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Specify your S3 bucket and prefix
s3_bucket = 'lambda-code-bucket-for-tests'
s3_prefix = 'jsons/'  # e.g., 'json-files/'

# Read data from S3
datasource0 = glueContext.create_dynamic_frame.from_options(
    's3',
    {'paths': [f's3://{s3_bucket}/{s3_prefix}']},
    'json'
)

# Convert DynamicFrame to DataFrame for easier manipulation
df = datasource0.toDF()

# Explode the 'states' array and then select the individual fields
df_exploded = df.select(explode(col("states")).alias("state"))
df_flattened = df_exploded.select(
    col("state").getItem(0).alias("icao24"),
    col("state").getItem(1).alias("callsign"),
    col("state").getItem(2).alias("origin_country"),
    col("state").getItem(3).alias("time_position")
)

# Debug: Print out the schema to confirm the structure
df_flattened.printSchema()

# Debug: Show a few rows to understand the actual data
df_flattened.show(5)

# Initialize a DynamoDB client
dynamodb = boto3.resource('dynamodb', region_name='eu-central-1')  # Make sure to specify the correct region
table = dynamodb.Table('OpenSkyData')

# Iterate over DataFrame rows and insert into DynamoDB
for row in df_flattened.collect():
    # Extract icao24 and time_position considering their nested Row structure
    # Assuming df_flattened already only contains the relevant "states" data as before
    icao24_value = row.icao24.string if row.icao24.string is not None else row.icao24.int
    callsign_value = row.callsign.string if row.callsign.string is not None else row.callsign.int
    origin_country_value = row.origin_country.string if row.origin_country.string is not None else row.origin_country.int
    time_position_value = row.time_position.int if row.time_position.int is not None else row.time_position.string

    # Convert time_position_value to int, ensuring it matches DynamoDB's expected format
    time_position_value = int(time_position_value)

    # Prepare item for DynamoDB insertion
    item = {
        'icao24': icao24_value,
        'callsign': callsign_value,
        'origin_country': origin_country_value,
        'time_position': time_position_value
    }

    # Insert item into DynamoDB (wrapped in try-except for safety)
    try:
        table.put_item(Item=item)
        print(f"Successfully inserted: {item}")
    except Exception as e:
        print(f"Error inserting item into DynamoDB: {e}")