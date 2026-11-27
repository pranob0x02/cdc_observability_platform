locals {
  redpanda_broker = format("%s.%s.svc.cluster.local:%s", "redpanda", var.redpanda_namespace, "9093")
  minio_s3_url    = format("%s://%s.%s.svc.cluster.local:%s", "http", "minio", "lakehouse", "9000")
}

resource "kubernetes_config_map" "spark_cdc_job" {
  metadata {
    name      = "spark-cdc-iceberg-script"
    namespace = kubernetes_namespace.lakehouse.id
  }

  data = {
    "stream_orders_to_iceberg.py" = <<-PYTHON
      import base64
      import os
      from pyspark.sql import SparkSession
      from pyspark.sql.functions import col, from_json, coalesce, current_timestamp, udf
      from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

      minio_endpoint = os.environ["MINIO_ENDPOINT"]
      minio_user = os.environ["MINIO_ROOT_USER"]
      minio_pass = os.environ["MINIO_ROOT_PASSWORD"]
      kafka_bootstrap = os.environ["KAFKA_BOOTSTRAP"]

      def decode_debezium_decimal(b64_str, scale):
          if not b64_str:
              return None
          raw = base64.b64decode(b64_str)
          unscaled = int.from_bytes(raw, byteorder="big", signed=True)
          return float(unscaled) / (10 ** scale)

      decode_price_udf = udf(lambda s: decode_debezium_decimal(s, 5), DoubleType())
      decode_qty_udf = udf(lambda s: decode_debezium_decimal(s, 2), DoubleType())

      spark = (
          SparkSession.builder.appName("RedpandaCDCToIceberg")
          .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
          .config("spark.sql.catalog.lakehouse", "org.apache.iceberg.spark.SparkCatalog")
          .config("spark.sql.catalog.lakehouse.type", "hadoop")
          .config("spark.sql.catalog.lakehouse.warehouse", "s3a://warehouse/iceberg")
          .config("spark.hadoop.fs.s3a.endpoint", minio_endpoint)
          .config("spark.hadoop.fs.s3a.access.key", minio_user)
          .config("spark.hadoop.fs.s3a.secret.key", minio_pass)
          .config("spark.hadoop.fs.s3a.path.style.access", "true")
          .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
          .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
          .getOrCreate()
      )

      spark.sparkContext.setLogLevel("WARN")
      spark.sql("CREATE NAMESPACE IF NOT EXISTS lakehouse.trading")
      spark.sql("""
          CREATE TABLE IF NOT EXISTS lakehouse.trading.orders_cdc (
              order_id INT,
              symbol STRING,
              side STRING,
              price DOUBLE,
              quantity DOUBLE,
              status STRING,
              cdc_op STRING,
              ingested_at TIMESTAMP
          )
          USING iceberg
          PARTITIONED BY (symbol)
      """)

      row_schema = StructType([
          StructField("order_id", IntegerType()),
          StructField("symbol", StringType()),
          StructField("side", StringType()),
          StructField("price", StringType()),
          StructField("quantity", StringType()),
          StructField("status", StringType()),
      ])

      inner_schema = StructType([
          StructField("before", row_schema),
          StructField("after", row_schema),
          StructField("op", StringType()),
      ])

      envelope_schema = StructType([
          StructField("payload", inner_schema),
      ])

      raw_stream = (
          spark.readStream.format("kafka")
          .option("kafka.bootstrap.servers", kafka_bootstrap)
          .option("subscribe", "cdc.public.orders")
          .option("startingOffsets", "earliest")
          .option("failOnDataLoss", "false")
          .load()
      )

      parsed_df = (
          raw_stream.select(from_json(col("value").cast("string"), envelope_schema).alias("env"))
          .select(
              coalesce(col("env.payload.after"), col("env.payload.before")).alias("row"),
              col("env.payload.op").alias("cdc_op"),
          )
          .select(
              col("row.order_id").alias("order_id"),
              col("row.symbol").alias("symbol"),
              col("row.side").alias("side"),
              decode_price_udf(col("row.price")).alias("price"),
              decode_qty_udf(col("row.quantity")).alias("quantity"),
              col("row.status").alias("status"),
              col("cdc_op"),
              current_timestamp().alias("ingested_at"),
          )
          .filter(col("order_id").isNotNull())
      )

      query = (
          parsed_df.writeStream.format("iceberg")
          .outputMode("append")
          .trigger(processingTime="10 seconds")
          .option("path", "lakehouse.trading.orders_cdc")
          .option("checkpointLocation", "s3a://checkpoints/orders_cdc_v3/")
          .start()
      )

      query.awaitTermination()
    PYTHON
  }
}

resource "kubernetes_deployment" "spark_cdc_consumer" {
  metadata {
    name      = "spark-cdc-iceberg"
    namespace = kubernetes_namespace.lakehouse.id
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "spark-cdc-iceberg" }
    }

    template {
      metadata {
        labels = { app = "spark-cdc-iceberg" }
        annotations = {
          "script-hash" = sha256(kubernetes_config_map.spark_cdc_job.data["stream_orders_to_iceberg.py"])
        }
      }

      spec {
        container {
          name  = "spark"
          image = "apache/spark:3.5.3"

          command = [
            "/opt/spark/bin/spark-submit",
            "--master", "local",
            "--conf", "spark.jars.ivy=/tmp/.ivy2",
            "--packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.3,org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.6.1,org.apache.hadoop:hadoop-aws:3.3.4",
            "/opt/spark/work-dir/stream_orders_to_iceberg.py"
          ]

          env {
            name  = "MINIO_ENDPOINT"
            value = local.minio_s3_url
          }
          env {
            name  = "KAFKA_BOOTSTRAP"
            value = local.redpanda_broker
          }
          env_from {
            secret_ref {
              name = "minio-credentials"
            }
          }

          resources {
            requests = { memory = "1Gi", cpu = "500m" }
            limits   = { memory = "2Gi", cpu = "1500m" }
          }

          volume_mount {
            name       = "script"
            mount_path = "/opt/spark/work-dir"
          }
        }

        volume {
          name = "script"
          config_map {
            name = "spark-cdc-iceberg-script"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.minio,
    kubernetes_job.create_minio_buckets
  ]
}
