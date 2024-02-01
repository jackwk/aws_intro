import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import col, explode, from_unixtime
from awsglue.dynamicframe import DynamicFrame
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'database', 'table_name'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database = args['database'],
    table_name = args['table_name'],
    transformation_ctx = "datasource0"
)

# Convert DynamicFrame to DataFrame for more complex transformations
df = datasource0.toDF()

# Explode the states array into separate rows
df = df.withColumn("state", explode(df.states)).drop("states", "time")

# Selecting and renaming the columns based on OpenSky API fields
df = df.select(
    col("state").getItem(0).alias("icao24"),
    col("state").getItem(1).alias("callsign"),
    col("state").getItem(2).alias("origin_country"),
    from_unixtime(col("state").getItem(3)).alias("time_position"),
    from_unixtime(col("state").getItem(4)).alias("last_contact"),
    col("state").getItem(5).alias("longitude"),
    col("state").getItem(6).alias("latitude"),
    col("state").getItem(7).alias("altitude"),
    col("state").getItem(8).alias("on_ground"),
    col("state").getItem(9).alias("velocity"),
    col("state").getItem(10).alias("true_track"),
    col("state").getItem(11).alias("vertical_rate"),
    col("state").getItem(12).alias("sensors"),
    col("state").getItem(13).alias("geo_altitude"),
    col("state").getItem(14).alias("squawk"),
    col("state").getItem(15).alias("spi"),
    col("state").getItem(16).alias("position_source")
)

# Convert DataFrame back to DynamicFrame
transformed_data = DynamicFrame.fromDF(df, glueContext, "transformed_data")

datasink4 = glueContext.write_dynamic_frame.from_options(
    frame = transformed_data,
    connection_type = "s3",
    connection_options = {"path": "s3://your-output-s3-bucket/output-path/"},
    format = "json"
)

job.commit()
