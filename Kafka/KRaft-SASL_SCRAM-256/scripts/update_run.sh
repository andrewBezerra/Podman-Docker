#!/bin/sh

file_path="/tmp/clusterID/clusterID"
interval=5  # wait interval in seconds

while [ ! -e "$file_path" ] || [ ! -s "$file_path" ]; do
  echo "Waiting for $file_path to be created..."
  sleep $interval
done

export CLUSTER_ID=$(cat "$file_path")

JAAS_FILE=/etc/kafka/kafka_server_jaas.conf
cat <<EOF > $JAAS_FILE
KafkaServer {
   org.apache.kafka.common.security.scram.ScramLoginModule required
   username="controller"
   password="controller-secret"
   user_controller="controller-secret";
};
KafkaClient {
   org.apache.kafka.common.security.scram.ScramLoginModule required
   username="admin"
   password="admin-secret"
   user_admin="admin-secret";
};
Client {
   org.apache.kafka.common.security.scram.ScramLoginModule required
   username="admin"
   password="admin-secret"
   user_admin="admin-secret";
};
EOF

# KRaft required step: Format the storage directory with a new cluster ID
# Have to add \n not to corrupt /etc/confluent/docker/ensure
# --config CONFIG, -c CONFIG
#                        The Kafka configuration file to use.
# --cluster-id CLUSTER_ID, -t CLUSTER_ID
#                        The cluster ID to use.
# --add-scram ADD_SCRAM, -S ADD_SCRAM
#                        A SCRAM_CREDENTIAL to add to the __cluster_metadata log e.g.
#                        'SCRAM-SHA-256=[user=alice,password=alice-secret]'
#                        'SCRAM-SHA-512=[user=alice,iterations=8192,salt="N3E=",saltedpassword="YCE="]'
# --ignore-formatted, -g
# --release-version RELEASE_VERSION, -r RELEASE_VERSION
#                        A KRaft release version to use for the  initial  metadata version. The minimum is 3.0, the
#                        default is 3.5-IV2



. /etc/confluent/docker/bash-config

echo "===> User"
id

echo "===> Configuring ..."
/etc/confluent/docker/configure

echo "===> Cluster ID"
cat "$file_path"

# updated ensure bit
echo "===> Ensuring ..."
export KAFKA_DATA_DIRS=${KAFKA_DATA_DIRS:-"/var/lib/kafka/data"}
echo "===> Check if $KAFKA_DATA_DIRS is writable ..."
dub path "$KAFKA_DATA_DIRS" writable

if [[ -n "${KAFKA_ZOOKEEPER_SSL_CLIENT_ENABLE-}" ]] && [[ $KAFKA_ZOOKEEPER_SSL_CLIENT_ENABLE == "true" ]]
then
    echo "===> Skipping Zookeeper health check for SSL connections..."
elif [[ -n "${KAFKA_PROCESS_ROLES-}" ]]
then 
    echo "===> Running in KRaft mode, skipping Zookeeper health check..."
else
    echo "===> Check if Zookeeper is healthy ..."
    cub zk-ready "$KAFKA_ZOOKEEPER_CONNECT" "${KAFKA_CUB_ZK_TIMEOUT:-40}"
fi

echo "===> Adding scram users ..."
eval "kafka-storage format --add-scram 'SCRAM-SHA-256=[name=admin,password=admin-secret]' --add-scram 'SCRAM-SHA-256=[name=controller,password=controller-secret]' --ignore-formatted -t $(cat "$file_path") -c /etc/kafka/kafka.properties"


# KRaft required step: Format the storage directory with provided cluster ID unless it already exists.
if [[ -n "${KAFKA_PROCESS_ROLES-}" ]]
then
    echo "===> Using provided cluster id $CLUSTER_ID ..."

    # A bit of a hack to not error out if the storage is already formatted.  Need storage-tool to support this
    result=$(kafka-storage format --cluster-id=$CLUSTER_ID -c /etc/kafka/kafka.properties 2>&1) || \
        echo $result | grep -i "already formatted" || \
        { echo $result && (exit 1) }
fi


echo "===> Launching ... "
exec /etc/confluent/docker/launch