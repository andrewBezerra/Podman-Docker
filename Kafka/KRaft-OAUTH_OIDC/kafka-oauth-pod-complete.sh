#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Kafka KRaft + OAuth/OIDC + Keycloak (Podman Pod)         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Limpar ambiente
echo "===> Cleaning previous environment..."
podman pod rm -f kafka-pod 2>/dev/null || true
podman volume rm -f kafka-data 2>/dev/null || true
rm -rf clusterID/* 2>/dev/null || true

# Criar diretórios
mkdir -p clusterID scripts

# ============================================================
# SCRIPTS
# ============================================================

cat > scripts/create_cluster_id.sh << 'EOF'
#!/bin/bash
file_path="/tmp/clusterID/clusterID"
if [ ! -f "$file_path" ]; then
  /bin/kafka-storage random-uuid > /tmp/clusterID/clusterID
  echo "Cluster ID created: $(cat $file_path)"
else
  echo "Cluster ID exists: $(cat $file_path)"
fi
EOF

cat > scripts/format_storage.sh << 'EOF'
#!/bin/sh
set -e
file_path="/tmp/clusterID/clusterID"
interval=5
echo "===> Waiting for cluster ID..."
while [ ! -e "$file_path" ] || [ ! -s "$file_path" ]; do
  echo "Waiting..."
  sleep $interval
done
echo "===> Cluster ID found: $(cat $file_path)"
. /etc/confluent/docker/bash-config
/etc/confluent/docker/configure
echo "===> Formatting storage..."
kafka-storage format --ignore-formatted -t $(cat "$file_path") -c /etc/kafka/kafka.properties
echo "===> Storage formatted!"
EOF

cat > scripts/configure_keycloak.sh << 'EOF'
#!/bin/bash
set -e

KEYCLOAK_URL="http://localhost:8080"
MAX_RETRIES=60
RETRY_DELAY=5

echo "===> Waiting for Keycloak to be ready..."
for i in $(seq 1 $MAX_RETRIES); do
  if curl -sf "${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
    echo "✅ Keycloak is ready!"
    break
  fi
  if [ $i -eq $MAX_RETRIES ]; then
    echo "❌ Keycloak failed to start"
    exit 1
  fi
  echo "Waiting... ($i/$MAX_RETRIES)"
  sleep $RETRY_DELAY
done

sleep 5

echo "===> Getting admin token..."
ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
  echo "❌ Failed to get admin token"
  exit 1
fi

echo "✅ Admin token obtained"

# Criar realm
echo "===> Creating realm kafka..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"realm":"kafka","enabled":true,"displayName":"Kafka OAuth Realm"}')

if [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Realm created"
elif [ "$HTTP_CODE" = "409" ]; then
  echo "ℹ️  Realm already exists"
else
  echo "⚠️  Realm status: $HTTP_CODE"
fi

sleep 2

# Criar client kafka-broker
echo "===> Creating client kafka-broker..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "kafka-broker",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "kafka-broker-secret",
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
  }' > /dev/null 2>&1 && echo "✅ Client kafka-broker created" || echo "ℹ️  Client kafka-broker exists"

sleep 1

# Criar client kafka-client
echo "===> Creating client kafka-client..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "kafka-client",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "kafka-client-secret",
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "publicClient": false,
    "protocol": "openid-connect"
  }' > /dev/null 2>&1 && echo "✅ Client kafka-client created" || echo "ℹ️  Client kafka-client exists"

sleep 1

# Criar usuários
echo "===> Creating users..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"username":"kafka-admin","enabled":true,"credentials":[{"type":"password","value":"admin-password","temporary":false}]}' \
  > /dev/null 2>&1 && echo "✅ User kafka-admin created" || echo "ℹ️  User kafka-admin exists"

curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"username":"kafka-producer","enabled":true,"credentials":[{"type":"password","value":"producer-password","temporary":false}]}' \
  > /dev/null 2>&1 && echo "✅ User kafka-producer created" || echo "ℹ️  User kafka-producer exists"

curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"username":"kafka-consumer","enabled":true,"credentials":[{"type":"password","value":"consumer-password","temporary":false}]}' \
  > /dev/null 2>&1 && echo "✅ User kafka-consumer created" || echo "ℹ️  User kafka-consumer exists"

echo ""
echo "✅ Keycloak configuration completed!"
EOF

chmod +x scripts/*.sh

# ============================================================
# CRIAR POD
# ============================================================

echo ""
echo "===> Creating Podman Pod..."
podman pod create \
  --name kafka-pod \
  -p 9092:9092 \
  -p 8080:8080 \
  -p 8090:8090

echo "✅ Pod created"

# ============================================================
# 1. KEYCLOAK
# ============================================================

echo ""
echo "===> Starting Keycloak..."
podman run -d \
  --pod kafka-pod \
  --name keycloak \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  -e KC_HTTP_PORT=8080 \
  -e KC_HOSTNAME_STRICT=false \
  -e KC_HOSTNAME_STRICT_HTTPS=false \
  -e KC_HTTP_ENABLED=true \
  -e KC_HEALTH_ENABLED=true \
  quay.io/keycloak/keycloak:23.0 \
  start-dev

echo "⏳ Waiting for Keycloak to start (60s)..."
sleep 60

# ============================================================
# 2. CONFIGURAR KEYCLOAK
# ============================================================

echo ""
echo "===> Configuring Keycloak..."
podman run --rm \
  --pod kafka-pod \
  -v ./scripts:/scripts:z \
  alpine:latest \
  sh -c "apk add --no-cache curl jq bash > /dev/null 2>&1 && bash /scripts/configure_keycloak.sh"

# ============================================================
# 3. GERAR CLUSTER ID
# ============================================================

echo ""
echo "===> Generating Kafka cluster ID..."
podman run --rm \
  -v ./clusterID:/tmp/clusterID:z \
  -v ./scripts:/tmp/scripts:z \
  confluentinc/cp-kafka:7.5.0 \
  bash /tmp/scripts/create_cluster_id.sh

# ============================================================
# 4. KAFKA COM OAUTH
# ============================================================

podman volume create kafka-data > /dev/null

echo ""
echo "===> Starting Kafka with OAuth/OIDC..."
podman run -d \
  --pod kafka-pod \
  --name kafka \
  -v kafka-data:/var/lib/kafka/data:z \
  -v ./scripts:/tmp/scripts:z \
  -v ./clusterID:/tmp/clusterID:z \
  -e CLUSTER_ID="MkU3OEVBNTcwNTJENDM2Qk" \
  -e KAFKA_NODE_ID=1 \
  -e KAFKA_PROCESS_ROLES="broker,controller" \
  -e KAFKA_CONTROLLER_QUORUM_VOTERS="1@localhost:29092" \
  -e KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER \
  -e KAFKA_INTER_BROKER_LISTENER_NAME=SASL_PLAINTEXT \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP="CONTROLLER:PLAINTEXT,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_PLAINTEXT_HOST:SASL_PLAINTEXT" \
  -e KAFKA_LISTENERS="SASL_PLAINTEXT://localhost:19092,SASL_PLAINTEXT_HOST://0.0.0.0:9092,CONTROLLER://localhost:29092" \
  -e KAFKA_ADVERTISED_LISTENERS="SASL_PLAINTEXT://localhost:19092,SASL_PLAINTEXT_HOST://localhost:9092" \
  -e KAFKA_SASL_ENABLED_MECHANISMS=OAUTHBEARER \
  -e KAFKA_SASL_MECHANISM_INTER_BROKER_PROTOCOL=OAUTHBEARER \
  -e KAFKA_SASL_MECHANISM_CONTROLLER_PROTOCOL=PLAIN \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_SASL_ENABLED_MECHANISMS=OAUTHBEARER \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_OAUTHBEARER_SASL_JAAS_CONFIG='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.jwks.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/certs" oauth.valid.issuer.uri="http://localhost:8080/realms/kafka" oauth.token.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/token" oauth.client.id="kafka-broker" oauth.client.secret="kafka-broker-secret" oauth.username.claim="preferred_username";' \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_OAUTHBEARER_SASL_SERVER_CALLBACK_HANDLER_CLASS=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerValidatorCallbackHandler \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_OAUTHBEARER_SASL_LOGIN_CALLBACK_HANDLER_CLASS=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_HOST_SASL_ENABLED_MECHANISMS=OAUTHBEARER \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_HOST_OAUTHBEARER_SASL_JAAS_CONFIG='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.jwks.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/certs" oauth.valid.issuer.uri="http://localhost:8080/realms/kafka" oauth.token.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/token" oauth.client.id="kafka-broker" oauth.client.secret="kafka-broker-secret" oauth.username.claim="preferred_username";' \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_HOST_OAUTHBEARER_SASL_SERVER_CALLBACK_HANDLER_CLASS=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerValidatorCallbackHandler \
  -e KAFKA_LISTENER_NAME_SASL_PLAINTEXT_HOST_OAUTHBEARER_SASL_LOGIN_CALLBACK_HANDLER_CLASS=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler \
  -e KAFKA_LISTENER_NAME_CONTROLLER_SASL_ENABLED_MECHANISMS=PLAIN \
  -e KAFKA_LISTENER_NAME_CONTROLLER_PLAIN_SASL_JAAS_CONFIG='org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret" user_admin="admin-secret";' \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1 \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1 \
  -e KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0 \
  -e KAFKA_LOG_DIRS="/tmp/kraft-combined-logs" \
  -e KAFKA_ALLOW_EVERYONE_IF_NO_ACL_FOUND=true \
  confluentinc/cp-kafka:7.5.0 \
  bash -c '/tmp/scripts/format_storage.sh && /etc/confluent/docker/run'

echo "⏳ Waiting for Kafka to start (40s)..."
sleep 40

# Verificar Kafka
if podman exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092 > /dev/null 2>&1; then
  echo "✅ Kafka is running!"
else
  echo "⚠️  Kafka may still be starting..."
fi

# ============================================================
# 5. KAFKA UI
# ============================================================

echo ""
echo "===> Starting Kafka UI..."
podman run -d \
  --pod kafka-pod \
  --name kafka-ui \
  -e KAFKA_CLUSTERS_0_NAME=kafka-oauth \
  -e KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS=localhost:9092 \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL=SASL_PLAINTEXT \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SASL_MECHANISM=OAUTHBEARER \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SASL_JAAS_CONFIG='org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.token.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/token" oauth.client.id="kafka-client" oauth.client.secret="kafka-client-secret";' \
  -e KAFKA_CLUSTERS_0_PROPERTIES_SASL_LOGIN_CALLBACK_HANDLER_CLASS=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler \
  provectuslabs/kafka-ui:latest

echo "✅ Kafka UI started"

# ============================================================
# RESUMO
# ============================================================

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ✅ SETUP COMPLETED!                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Access URLs:"
echo "  🔐 Keycloak Admin:  http://localhost:8080"
echo "     Username: admin"
echo "     Password: admin"
echo "     Realm: kafka"
echo ""
echo "  📈 Kafka UI:        http://localhost:8090"
echo ""
echo "  ⚡ Kafka Broker:    localhost:9092 (SASL_PLAINTEXT with OAuth)"
echo ""
echo "🔑 OAuth Clients:"
echo "  • kafka-broker / kafka-broker-secret"
echo "  • kafka-client / kafka-client-secret"
echo ""
echo "👥 Users:"
echo "  • kafka-admin / admin-password"
echo "  • kafka-producer / producer-password"
echo "  • kafka-consumer / consumer-password"
echo ""
echo "🔧 Useful commands:"
echo "  podman pod ps                    # View pod status"
echo "  podman ps                        # View containers"
echo "  podman logs -f kafka             # View Kafka logs"
echo "  podman logs -f kafka-ui          # View Kafka UI logs"
echo "  podman logs -f keycloak          # View Keycloak logs"
echo "  podman pod stop kafka-pod        # Stop all services"
echo "  podman pod start kafka-pod       # Start all services"
echo "  podman pod rm -f kafka-pod       # Remove pod"
echo ""
echo "🧪 Test OAuth token:"
echo '  curl -s -X POST "http://localhost:8080/realms/kafka/protocol/openid-connect/token" \'
echo '    -d "username=kafka-admin" \'
echo '    -d "password=admin-password" \'
echo '    -d "grant_type=password" \'
echo '    -d "client_id=kafka-client" \'
echo '    -d "client_secret=kafka-client-secret" | jq -r ".access_token"'
echo ""
echo "📝 Create Kafka topic with OAuth:"
echo '  podman exec -it kafka bash -c '"'"'cat > /tmp/client.properties << EOF'
echo 'security.protocol=SASL_PLAINTEXT'
echo 'sasl.mechanism=OAUTHBEARER'
echo 'sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required oauth.token.endpoint.uri="http://localhost:8080/realms/kafka/protocol/openid-connect/token" oauth.client.id="kafka-client" oauth.client.secret="kafka-client-secret";'
echo 'sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.secured.OAuthBearerLoginCallbackHandler'
echo 'EOF'
echo "  kafka-topics --bootstrap-server localhost:9092 --command-config /tmp/client.properties --create --topic test --partitions 3 --replication-factor 1'"
echo ""