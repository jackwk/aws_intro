import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import explode, col, input_file_name

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Specify your S3 bucket and prefix
s3_bucket = 'lambda-code-bucket-for-tests'
s3_prefix = 'jsons/'

# Read data from S3
datasource0 = glueContext.create_dynamic_frame.from_options(
    's3',
    {'paths': [f's3://{s3_bucket}/{s3_prefix}']},
    'json'
)

# Convert DynamicFrame to DataFrame for easier manipulation
df = datasource0.toDF()
df = df.withColumn("input_file_name", input_file_name())

# Process each file separately
s3_paths = df.select("input_file_name").distinct().collect()
for path in s3_paths:
    file_name = path.input_file_name
    print(f"Processing file: {file_name}")  # Replaced logger.info with print
    
    # Filter the dataframe for the current file being processed
    df_filtered = df.filter(df.input_file_name == file_name)
    
    # Explode, transform, and filter as before
    df_exploded = df_filtered.select(
        explode(df_filtered['states']).alias('state')
    ).select(
        col('state').getItem(0).alias('icao24'),
        col('state').getItem(1).cast('long').alias('time_position')
    ).filter(col('time_position').isNotNull())
    
    record_count = df_exploded.count()
    
    # Initialize a DynamoDB client
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('OpenSkyData')
    
    # Iterate over DataFrame rows and insert into DynamoDB
    for row in df_exploded.collect():
        item = {
            'icao24': row['icao24'],
            'time_position': row['time_position']
        }
        table.put_item(Item=item)
    
    print(f"Successfully saved {record_count} records to DynamoDB for file: {file_name}")  # Replaced logger.info with print

print("Data insertion completed.")
