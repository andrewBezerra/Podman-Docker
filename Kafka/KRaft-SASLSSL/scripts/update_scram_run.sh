#!/bin/sh
set -e

file_path="/tmp/clusterID/clusterID"
interval=5

echo "===> Waiting for cluster ID to be created..."
while [ ! -e "$file_path" ] || [ ! -s "$file_path" ]; do
  echo "Waiting for $file_path to be available..."
  sleep $interval
done

echo "===> Cluster ID found: $(cat $file_path)"

# Criar arquivo JAAS para o controller (usa PLAIN)
JAAS_FILE=/etc/kafka/kafka_server_jaas.conf
cat <<EOF > $JAAS_FILE
KafkaServer {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="admin-secret"
   user_admin="admin-secret";
};
KafkaClient {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="admin-secret";
};
Client {
   org.apache.kafka.common.security.plain.PlainLoginModule required
   username="admin"
   password="admin-secret";
};
EOF

echo "===> JAAS configuration file created at $JAAS_FILE"

# Carregar configurações do Confluent
. /etc/confluent/docker/bash-config

echo "===> Current user:"
id

echo "===> Configuring Kafka..."
/etc/confluent/docker/configure

# Formatar storage com todos os usuários SCRAM-SHA-512
echo "===> Formatting Kafka storage with SCRAM-SHA-512 credentials..."
kafka-storage format \
  --add-scram 'SCRAM-SHA-512=[name=admin,password=admin-secret]' \
  --add-scram 'SCRAM-SHA-512=[name=connect,password=connect-secret]' \
  --add-scram 'SCRAM-SHA-512=[name=schemaregistry,password=schemaregistry-secret]' \
  --add-scram 'SCRAM-SHA-512=[name=ksqldb,password=ksqldb-secret]' \
  --add-scram 'SCRAM-SHA-512=[name=tool,password=tool-secret]' \
  --ignore-formatted \
  -t $(cat "$file_path") \
  -c /etc/kafka/kafka.properties

echo "===> Kafka storage formatted successfully!"
echo "===> SCRAM-SHA-512 users created: admin, connect, schemaregistry, ksqldb, tool"