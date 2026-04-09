#!/bin/bash

file_path="/tmp/clusterID/clusterID"

if [ ! -f "$file_path" ]; then
  /bin/kafka-storage random-uuid > /tmp/clusterID/clusterID
  echo "Cluster ID created: $(cat $file_path)"
else
  echo "Cluster ID already exists: $(cat $file_path)"
fi