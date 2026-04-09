#!/bin/sh

file_path="/tmp/clusterID/clusterID"
interval=5  # wait interval in seconds

while [ ! -e "$file_path" ] || [ ! -s "$file_path" ]; do
  echo "Waiting for $file_path to be created..."
  sleep $interval
done

JAAS_FILE=/etc/kafka/kafka_server_jaas.conf
cat <<EOF > $JAAS_FILE
KafkaServer {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   serviceName="kafka-broker"
   username="controller"
   password="controller-secret"
   user_controller="controller-secret";
};
KafkaClient {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   serviceName="kafka-broker"
   username="controller"
   password="controller-secret"
   user_controller="controller-secret";
};
Client {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   serviceName="kafka-broker"
   username="controller"
   password="controller-secret"
   user_controller="controller-secret";
};
EOF

. /etc/confluent/docker/bash-config

echo "===> User"
id

echo "===> Configuring ..."
/etc/confluent/docker/configure

cat "$file_path"
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

# echo -e "\nkafka-storage format --add-scram 'SCRAM-SHA-256=[name=\"admin\",password=\"admin-secret\"]' --ignore-formatted -t $(cat "$file_path") -c /etc/kafka/kafka.properties" >> /etc/confluent/docker/ensure

eval "kafka-storage format --add-scram 'SCRAM-SHA-256=[name=\"admin\",password=\"admin-secret\"]' --ignore-formatted -t $(cat "$file_path") -c /etc/kafka/kafka.properties"
