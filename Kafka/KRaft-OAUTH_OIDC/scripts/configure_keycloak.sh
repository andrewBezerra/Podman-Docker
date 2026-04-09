#!/bin/bash
set -e

KEYCLOAK_URL="http://keycloak:8080"
MAX_RETRIES=60
RETRY_DELAY=5

echo "===> Waiting for Keycloak to be ready..."
for i in $(seq 1 $MAX_RETRIES); do
  if curl -sf "${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
    echo "✅ Keycloak is ready!"
    break
  fi
  if [ $i -eq $MAX_RETRIES ]; then
    echo "❌ Keycloak failed to start after ${MAX_RETRIES} attempts"
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

# Create realm
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
  echo "⚠️  Realm creation status: $HTTP_CODE"
fi

sleep 2

# Create client kafka-broker
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

# Create client kafka-client
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

# Create users
echo "===> Creating users..."

# kafka-admin
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "kafka-admin",
    "enabled": true,
    "credentials": [{
      "type": "password",
      "value": "admin-password",
      "temporary": false
    }]
  }' > /dev/null 2>&1 && echo "✅ User kafka-admin created" || echo "ℹ️  User kafka-admin exists"

# kafka-producer
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "kafka-producer",
    "enabled": true,
    "credentials": [{
      "type": "password",
      "value": "producer-password",
      "temporary": false
    }]
  }' > /dev/null 2>&1 && echo "✅ User kafka-producer created" || echo "ℹ️  User kafka-producer exists"

# kafka-consumer
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/kafka/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "kafka-consumer",
    "enabled": true,
    "credentials": [{
      "type": "password",
      "value": "consumer-password",
      "temporary": false
    }]
  }' > /dev/null 2>&1 && echo "✅ User kafka-consumer created" || echo "ℹ️  User kafka-consumer exists"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ✅ Keycloak Configuration Completed!              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Configuration Summary:"
echo "  Realm: kafka"
echo "  URL: ${KEYCLOAK_URL}"
echo ""
echo "  Clients:"
echo "    • kafka-broker / kafka-broker-secret"
echo "    • kafka-client / kafka-client-secret"
echo ""
echo "  Users:"
echo "    • kafka-admin / admin-password"
echo "    • kafka-producer / producer-password"
echo "    • kafka-consumer / consumer-password"
echo ""