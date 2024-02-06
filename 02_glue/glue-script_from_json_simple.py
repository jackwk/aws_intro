import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.transforms import *

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Specify your S3 bucket and prefix
s3_bucket = 'lambda-code-bucket-for-tests'
s3_prefix = 'jsons/' # e.g., 'json-files/'

# Read data from S3
datasource0 = glueContext.create_dynamic_frame.from_options(
    's3',
    {'paths': [f's3://{s3_bucket}/{s3_prefix}']},
    'json'
)

# Convert DynamicFrame to DataFrame for easier manipulation
df = datasource0.toDF()

# Initialize a DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('OpenSkyData')

# Iterate over DataFrame rows and insert into DynamoDB
for row in df.collect():
    # Convert row to dictionary and adjust field names if necessary
    item = {
        'icao24': row['icao24'],
        'time_position': int(row['time_position'])
    }
    print(f"Inserting record into DynamoDB: {item}")
    table.put_item(Item=item)

print("Data insertion completed.")
