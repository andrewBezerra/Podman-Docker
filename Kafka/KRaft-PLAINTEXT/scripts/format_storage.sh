#!/bin/sh
set -e

file_path="/tmp/clusterID/clusterID"
interval=5

echo "===> Waiting for cluster ID..."
while [ ! -e "$file_path" ] || [ ! -s "$file_path" ]; do
  echo "Waiting for $file_path..."
  sleep $interval
done

echo "===> Cluster ID found: $(cat $file_path)"

# Carregar configurações do Confluent
. /etc/confluent/docker/bash-config

echo "===> Configuring Kafka..."
/etc/confluent/docker/configure

# Formatar storage
echo "===> Formatting Kafka storage..."
kafka-storage format \
  --ignore-formatted \
  -t $(cat "$file_path") \
  -c /etc/kafka/kafka.properties

echo "===> Kafka storage formatted successfully!"