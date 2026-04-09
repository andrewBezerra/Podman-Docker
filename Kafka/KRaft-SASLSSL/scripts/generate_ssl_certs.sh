#!/bin/bash
set -e

VALIDITY_DAYS=365
PASSWORD="kafka-secret"
SECRETS_DIR="./secrets"

# Criar diretório de secrets
mkdir -p $SECRETS_DIR
cd $SECRETS_DIR

echo "===> Generating SSL certificates for Kafka..."

# 1. Gerar CA (Certificate Authority)
echo "1. Creating Certificate Authority (CA)..."
openssl req -new -x509 -keyout ca-key -out ca-cert -days $VALIDITY_DAYS -passout pass:$PASSWORD -subj "/C=BR/ST=SP/L=SaoPaulo/O=MyOrg/OU=IT/CN=KafkaCA"

# 2. Criar Truststore e importar CA
echo "2. Creating truststore and importing CA certificate..."
keytool -keystore kafka.truststore.jks -alias CARoot -import -file ca-cert -storepass $PASSWORD -keypass $PASSWORD -noprompt

# 3. Criar Keystore para o Broker
echo "3. Creating broker keystore..."
keytool -keystore kafka.keystore.jks -alias localhost -validity $VALIDITY_DAYS -genkey -keyalg RSA -storepass $PASSWORD -keypass $PASSWORD -dname "CN=kafka,OU=IT,O=MyOrg,L=SaoPaulo,ST=SP,C=BR" -ext SAN=DNS:kafka,DNS:localhost,IP:127.0.0.1

# 4. Criar Certificate Signing Request (CSR) para o broker
echo "4. Creating certificate signing request for broker..."
keytool -keystore kafka.keystore.jks -alias localhost -certreq -file cert-file -storepass $PASSWORD -keypass $PASSWORD

# 5. Assinar o certificado do broker com a CA
echo "5. Signing broker certificate with CA..."
openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days $VALIDITY_DAYS -CAcreateserial -passin pass:$PASSWORD -extensions v3_req -extfile <(cat <<EOF
[v3_req]
subjectAltName = DNS:kafka,DNS:localhost,IP:127.0.0.1
EOF
)

# 6. Importar CA e certificado assinado no keystore do broker
echo "6. Importing CA certificate into broker keystore..."
keytool -keystore kafka.keystore.jks -alias CARoot -import -file ca-cert -storepass $PASSWORD -keypass $PASSWORD -noprompt

echo "7. Importing signed certificate into broker keystore..."
keytool -keystore kafka.keystore.jks -alias localhost -import -file cert-signed -storepass $PASSWORD -keypass $PASSWORD -noprompt

# 8. Criar keystore e truststore para clientes
echo "8. Creating client keystore..."
keytool -keystore client.keystore.jks -alias client -validity $VALIDITY_DAYS -genkey -keyalg RSA -storepass $PASSWORD -keypass $PASSWORD -dname "CN=client,OU=IT,O=MyOrg,L=SaoPaulo,ST=SP,C=BR"

echo "9. Creating client certificate signing request..."
keytool -keystore client.keystore.jks -alias client -certreq -file client-cert-file -storepass $PASSWORD -keypass $PASSWORD

echo "10. Signing client certificate with CA..."
openssl x509 -req -CA ca-cert -CAkey ca-key -in client-cert-file -out client-cert-signed -days $VALIDITY_DAYS -CAcreateserial -passin pass:$PASSWORD

echo "11. Importing CA certificate into client keystore..."
keytool -keystore client.keystore.jks -alias CARoot -import -file ca-cert -storepass $PASSWORD -keypass $PASSWORD -noprompt

echo "12. Importing signed certificate into client keystore..."
keytool -keystore client.keystore.jks -alias client -import -file client-cert-signed -storepass $PASSWORD -keypass $PASSWORD -noprompt

# 9. Copiar truststore para cliente
echo "13. Copying truststore for client..."
cp kafka.truststore.jks client.truststore.jks

# Limpar arquivos temporários
echo "14. Cleaning up temporary files..."
rm -f cert-file cert-signed client-cert-file client-cert-signed

echo ""
echo "===> SSL certificates generated successfully!"
echo ""
echo "Generated files:"
echo "  - kafka.keystore.jks      (broker keystore)"
echo "  - kafka.truststore.jks    (broker truststore)"
echo "  - client.keystore.jks     (client keystore)"
echo "  - client.truststore.jks   (client truststore)"
echo "  - ca-cert                 (CA certificate)"
echo ""
echo "Password for all stores: $PASSWORD"
echo ""

cd ..