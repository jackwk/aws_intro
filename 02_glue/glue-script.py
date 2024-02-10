import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import explode, col
from decimal import Decimal

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Specify your S3 bucket and prefix
s3_bucket = 'opensky-flights-json-bucket'


# Read data from S3
datasource0 = glueContext.create_dynamic_frame.from_options(
    's3',
    {'paths': [f's3://{s3_bucket}']},
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
    col("state").getItem(3).alias("time_position"),
    col("state").getItem(4).alias("last_contact"),
    col("state").getItem(5).alias("longitude"),
    col("state").getItem(6).alias("latitude"),
    col("state").getItem(7).alias("baro_altitude"),
    col("state").getItem(8).alias("on_ground"),
    col("state").getItem(9).alias("velocity"),
    col("state").getItem(10).alias("true_track"),
    col("state").getItem(11).alias("vertical_rate"),
    col("state").getItem(12).alias("sensors"),
    col("state").getItem(13).alias("geo_altitude"),
    col("state").getItem(14).alias("squawk"),
    col("state").getItem(15).alias("spi"),
    col("state").getItem(16).alias("position_source"),
    col("state").getItem(17).alias("category")
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
    # Function to extract the correct value from struct based on type precedence: string -> double -> int
    def get_value(field):
        if field is None:
            return None
        if field.string is not None:
            return field.string
        elif field.double is not None:
            return field.double
        elif field.int is not None:
            return field.int
        else:
            return None

    # Extract and convert fields considering their nested struct structure
    icao24_value = get_value(row.icao24)
    callsign_value = get_value(row.callsign)
    origin_country_value = get_value(row.origin_country)
    time_position_value = get_value(row.time_position)
    last_contact_value = get_value(row.last_contact)
    longitude_value = get_value(row.longitude)
    latitude_value = get_value(row.latitude)
    baro_altitude_value = get_value(row.baro_altitude)
    on_ground_value = get_value(row.on_ground)
    velocity_value = get_value(row.velocity)
    true_track_value = get_value(row.true_track)
    vertical_rate_value = get_value(row.vertical_rate)
    sensors_value = get_value(row.sensors)
    geo_altitude_value = get_value(row.geo_altitude)
    squawk_value = get_value(row.squawk)
    spi_value = get_value(row.spi)
    position_source_value = get_value(row.position_source)
    category_value = get_value(row.category)

    # Convert numeric fields to appropriate types, handling None values
    if time_position_value is not None:
        time_position_value = int(time_position_value)
    if last_contact_value is not None:
        last_contact_value = int(last_contact_value)
    if longitude_value is not None:
        longitude_value = Decimal(str(longitude_value))
    if latitude_value is not None:
        latitude_value = Decimal(str(latitude_value))
    if baro_altitude_value is not None:
        baro_altitude_value = Decimal(str(baro_altitude_value))
    if velocity_value is not None:
        velocity_value = Decimal(str(velocity_value))
    if true_track_value is not None:
        true_track_value = Decimal(str(true_track_value))
    if vertical_rate_value is not None:
        vertical_rate_value = Decimal(str(vertical_rate_value))
    if sensors_value is not None:
        sensors_value = str(sensors_value)
    if geo_altitude_value is not None:
        geo_altitude_value = str(geo_altitude_value)
    if squawk_value is not None:
        squawk_value = str(squawk_value)
    if category_value is not None:
        category_value = str(category_value)

    # Prepare item for DynamoDB insertion
    item = {
        'icao24': str(icao24_value) if icao24_value is not None else None,
        'callsign': str(callsign_value) if callsign_value is not None else None,
        'origin_country': str(origin_country_value) if origin_country_value is not None else None,
        'time_position': time_position_value,
        'last_contact': last_contact_value,
        'longitude': longitude_value,
        'latitude': latitude_value,
        'baro_altitude': baro_altitude_value,
        'on_ground': on_ground_value,
        'velocity': velocity_value,
        'true_track': true_track_value,
        'vertical_rate': vertical_rate_value,
        'sensors': sensors_value,
        'geo_altitude': geo_altitude_value,
        'squawk': squawk_value,
        'spi': spi_value,
        'position_source': position_source_value,
        'category': category_value
    }

    # Insert item into DynamoDB (wrapped in try-except for safety)
    try:
        table.put_item(Item=item)
        print(f"Successfully inserted: {item}")
    except Exception as e:
        print(f"Error inserting item into DynamoDB: {e}")        