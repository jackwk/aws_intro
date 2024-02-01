import os
import json
import requests
import boto3
from datetime import datetime

def lambda_handler(event, context):
    # Fetch bucket name from Lambda environment variable
    bucket_name = os.environ['BUCKET_NAME']

    # Define the geographical bounds of Poland
    bounds = (49.00, 54.83, 14.12, 24.15)  # min latitude, max latitude, min longitude, max longitude

    # OpenSky API endpoint
    url = f"https://opensky-network.org/api/states/all?lamin={bounds[0]}&lamax={bounds[1]}&lomin={bounds[2]}&lomax={bounds[3]}"

    # Make the API request
    response = requests.get(url)
    if response.status_code != 200:
        return {
            'statusCode': response.status_code,
            'body': json.dumps('Failed to get data from OpenSky API')
        }

    # Data to be saved on S3
    data = response.json()

    # Save to S3
    s3 = boto3.client('s3')
    key = f"flights-{datetime.now().isoformat()}.json"
    s3.put_object(Bucket=bucket_name, Key=key, Body=json.dumps(data))

    return {
        'statusCode': 200,
        'body': json.dumps(f'Data saved to {bucket_name}/{key}')
    }
