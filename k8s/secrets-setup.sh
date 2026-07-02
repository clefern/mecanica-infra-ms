#!/usr/bin/env bash
# Setup de K8s Secrets para o namespace mecanica-ms.
# Pré-requisito: kubectl configurado e apontando para o cluster correto.
# Ajustar todos os valores <placeholder> antes de executar.
# Executar após: kubectl apply -k k8s/

set -euo pipefail

NAMESPACE=mecanica-ms

RDS_HOST=<rds-endpoint>           # ex: mecanica-db.xxxxxx.us-east-1.rds.amazonaws.com
RMQ_HOST=<rabbitmq-host>           # ex: rabbitmq.mecanica-ms.svc.cluster.local ou IP externo
DB_USER=mecanica
DB_PASS=<db-password>
RMQ_USER=mecanica
RMQ_PASS=<rabbitmq-password>
JWT_SECRET=<security-jwt-secret-key>
MP_TOKEN=<mercadopago-access-token>
NR_LICENSE_KEY=<new-relic-license-key>    # obter em one.newrelic.com/api-keys

kubectl create secret generic ms-shared-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-user="$DB_USER" \
  --from-literal=db-pass="$DB_PASS" \
  --from-literal=rabbitmq-host="$RMQ_HOST" \
  --from-literal=rabbitmq-user="$RMQ_USER" \
  --from-literal=rabbitmq-pass="$RMQ_PASS" \
  --from-literal=jwt-secret="$JWT_SECRET"

kubectl create secret generic os-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5432/os_service"

kubectl create secret generic billing-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5433/billing_service" \
  --from-literal=mp-access-token="$MP_TOKEN"

kubectl create secret generic inventory-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5434/inventory_service"

kubectl create secret generic workshop-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=mongodb-uri="mongodb://$RDS_HOST:27017/workshop_service"

kubectl create secret generic nr-secret \
  --namespace "$NAMESPACE" \
  --from-literal=license-key="$NR_LICENSE_KEY"

echo "Secrets criados em namespace $NAMESPACE."
