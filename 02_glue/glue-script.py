import boto3
from datetime import datetime

# Initialize a DynamoDB client
dynamodb = boto3.resource('dynamodb')

# Specify the DynamoDB table
table = dynamodb.Table('OpenSkyData')

# Example dummy data to insert
dummy_data = [
    {"icao24": "dummy1", "time_position": int(datetime.now().timestamp())},
    {"icao24": "dummy2", "time_position": int(datetime.now().timestamp() + 1)},
    {"icao24": "dummy3", "time_position": int(datetime.now().timestamp() + 2)},
]

# Insert dummy data into the DynamoDB table
for record in dummy_data:
    print(f"Inserting record into DynamoDB: {record}")
    table.put_item(Item=record)

print("Dummy data insertion completed.")
