import json
import boto3
import os
from datetime import datetime
from opensky_api import OpenSkyApi

def lambda_handler(event, context):
    # Define the bounding box for Poland
    bbox = [49.00, 14.00, 55.00, 24.00]

    # Initialize the OpenSky API
    api = OpenSkyApi()

    # Fetch current state vectors (flights) within the bounding box
    states = api.get_states(bbox=bbox)

    # Prepare the data for saving
    flights_data = []
    for s in states.states:
        flights_data.append({
            "icao24": s.icao24,
            "callsign": s.callsign,
            "origin_country": s.origin_country,
            "time_position": s.time_position,
            "longitude": s.longitude,
            "latitude": s.latitude,
            "altitude": s.baro_altitude,
            "velocity": s.velocity
            # Add more fields as needed
        })

    # Convert data to JSON
    json_data = json.dumps(flights_data)

    # Save to S3
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']  # Get bucket name from environment variable
    timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
    file_name = f'flights_data_{timestamp}.json'  # File name with timestamp
    s3.put_object(Bucket=bucket_name, Key=file_name, Body=json_data)

    return {
        'statusCode': 200,
        'body': json.dumps(f'File {file_name} successfully saved to S3 bucket {bucket_name}')
    }
