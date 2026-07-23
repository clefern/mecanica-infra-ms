#!/usr/bin/env bash
# Setup de K8s Secrets para o namespace mecanica-ms.
# Pré-requisito: kubectl configurado e apontando para o cluster correto.
# Ajustar todos os valores <placeholder> antes de executar.
#
# Ordem de bootstrap:
#   1. kubectl apply -k k8s/           (namespace, deployments, services, ingressroute)
#   2. bash  k8s/secrets-setup.sh      (este script)
#   3. kubectl apply -f k8s/db-init-job.yaml   (cria os 3 bancos no RDS)
#
# Topologia de dados (Fase 4):
#   - 1 instância RDS PostgreSQL única (barata p/ AWS Academy) com 3 bancos
#     lógicos isolados: os_service, billing_service, inventory_service.
#     Todos no mesmo host, porta 5432, cada MS conectando ao SEU banco.
#   - workshop-service usa MongoDB in-cluster (Helm release mecanica-mongodb).

set -euo pipefail

NAMESPACE=mecanica-ms

# --- RDS PostgreSQL (compartilhado; obter do output do fiap-tc-mecanica-infra-db
#     ou do Secrets Manager: aws secretsmanager get-secret-value --secret-id lab/mecanica/db) ---
RDS_HOST="<rds-endpoint>"          # ex: lab-mecanica-pg.xxxxxx.us-east-1.rds.amazonaws.com
DB_USER="<rds-master-username>"    # ex: mecanica_user
DB_PASS="<rds-master-password>"
RDS_MAINTENANCE_DB=mecanica        # banco inicial da instância (db_name do Terraform)

# --- MongoDB in-cluster (Helm) ---
MONGO_HOST=mecanica-mongodb.mecanica-ms.svc.cluster.local

# --- RabbitMQ (Helm release mecanica-rabbitmq) ---
RMQ_HOST=mecanica-rabbitmq.mecanica-ms.svc.cluster.local
RMQ_USER=guest
RMQ_PASS=guest

# --- App / integrações ---
JWT_SECRET="<security-jwt-secret-key>"
MP_TOKEN="<mercadopago-access-token>"
NR_LICENSE_KEY="<new-relic-license-key>"  # obter em one.newrelic.com/api-keys

# Credenciais compartilhadas (usuário/senha do RDS são os mesmos p/ os 3 bancos)
kubectl create secret generic ms-shared-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-user="$DB_USER" \
  --from-literal=db-pass="$DB_PASS" \
  --from-literal=rabbitmq-host="$RMQ_HOST" \
  --from-literal=rabbitmq-user="$RMQ_USER" \
  --from-literal=rabbitmq-pass="$RMQ_PASS" \
  --from-literal=jwt-secret="$JWT_SECRET"

# Credenciais administrativas usadas pelo db-init-job.yaml para criar os bancos.
kubectl create secret generic rds-admin-secret \
  --namespace "$NAMESPACE" \
  --from-literal=host="$RDS_HOST" \
  --from-literal=port="5432" \
  --from-literal=user="$DB_USER" \
  --from-literal=password="$DB_PASS" \
  --from-literal=maintenance-db="$RDS_MAINTENANCE_DB"

kubectl create secret generic os-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5432/os_service"

kubectl create secret generic billing-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5432/billing_service" \
  --from-literal=mp-access-token="$MP_TOKEN"

kubectl create secret generic inventory-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=db-url="jdbc:postgresql://$RDS_HOST:5432/inventory_service"

kubectl create secret generic workshop-service-secret \
  --namespace "$NAMESPACE" \
  --from-literal=mongodb-uri="mongodb://$MONGO_HOST:27017/workshop_service"

kubectl create secret generic nr-secret \
  --namespace "$NAMESPACE" \
  --from-literal=license-key="$NR_LICENSE_KEY"

echo "Secrets criados em namespace $NAMESPACE."
echo "Próximo passo: kubectl apply -f k8s/db-init-job.yaml"
