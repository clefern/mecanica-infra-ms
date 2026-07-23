# mecanica-infra-ms

Infraestrutura dos microsserviços da **Fase 4 — Mecânica API** (Grupo 14SOAT).

## Estrutura

```
mecanica-fiap/  ← docker-compose para desenvolvimento local (leia mecanica-fiap/README.md)
k8s/            ← manifestos Kubernetes (Namespace, Deployments, Services, secrets-setup.sh)
helm/           ← Helm charts: RabbitMQ, MongoDB (a preencher — Frente B)
scripts/        ← smoke-test.sh (valida Saga completa end-to-end)
```

## Desenvolvimento local

Para rodar a stack completa localmente (4 MS + Traefik + RabbitMQ + 3×PostgreSQL + MongoDB + ferramentas de UI) e consumir as APIs via Insomnia, siga o guia detalhado:

**[→ mecanica-fiap/README.md](mecanica-fiap/README.md)**

TL;DR:
```bash
cd mecanica-fiap/
cp .env.example .env          # editar: GITHUB_TOKEN obrigatório; DOCKER_SOCK no macOS
docker compose -f docker-compose.full.yml up --build
# Ponto único de entrada: http://localhost
# Login: POST http://localhost/api/auth/login  {"email":"admin@mecanica.com","password":"123456"}
```

## K8s — Deploy no cluster EKS

Pré-requisitos: `kubectl` configurado, cluster provisionado via `fiap-tc-mecanica-infra-k8s`, RDS via `fiap-tc-mecanica-infra-db`, RabbitMQ/MongoDB in-cluster (ver `helm/`).

```bash
# 1. Aplicar manifests (namespace, deployments, services, ingressroute)
kubectl apply -k k8s/

# 2. Criar K8s Secrets (editar os <placeholder> antes)
bash k8s/secrets-setup.sh

# 3. Criar os bancos por microsserviço no RDS (idempotente)
kubectl apply -f k8s/db-init-job.yaml
kubectl -n mecanica-ms wait --for=condition=complete job/db-init --timeout=120s

# 4. Verificar pods
kubectl get pods -n mecanica-ms
```

**Bancos de dados** (Fase 4 — cada MS com o seu): os/billing/inventory usam bancos
lógicos isolados (`os_service`, `billing_service`, `inventory_service`) numa única
instância RDS PostgreSQL (barato p/ AWS Academy); workshop usa MongoDB in-cluster.
Detalhes em [`k8s/README.md`](k8s/README.md).

Para atualizar a imagem de um MS, use o `cd.yml` (`workflow_dispatch`) no repositório do serviço.

## Portas locais

| Serviço | Porta | UI / endpoint |
|---------|-------|---------------|
| **Gateway (Traefik)** | **80** | **Ponto único de entrada — todos os MS** |
| Traefik dashboard | 8099 | http://localhost:8099 |
| os-service | 8080 | /swagger-ui.html |
| billing-service | 8081 | /swagger-ui.html |
| inventory-service | 8082 | /swagger-ui.html |
| workshop-service | 8083 | /swagger-ui.html |
| RabbitMQ AMQP | 5672 | — |
| RabbitMQ Management | 15672 | http://localhost:15672 |
| PostgreSQL os | 5432 | — |
| PostgreSQL billing | 5433 | — |
| PostgreSQL inventory | 5434 | — |
| MongoDB | 27017 | — |
| Adminer (Postgres UI) | 9090 | http://localhost:9090 |
| mongo-express (MongoDB UI) | 8084 | http://localhost:8084 |
| Mailhog SMTP | 1025 | — |
| Mailhog Web UI | 8025 | http://localhost:8025 |

## Repositórios do grupo

| Repositório | Responsabilidade |
|-------------|-----------------|
| mecanica-os-service | Orquestrador da Saga, lifecycle da OS |
| mecanica-billing-service | Orçamento + Mercado Pago |
| mecanica-inventory-service | Estoque, reserva e estorno de peças |
| mecanica-workshop-service | Execução física do reparo (MongoDB) |
| mecanica-shared-kernel | Value Objects compartilhados (GitHub Packages) |
| mecanica-infra-ms | **Este repositório** — infra local e K8s |
| fiap-tc-mecanica-infra-k8s | EKS, VPC, ECR (Terraform) |
| fiap-tc-mecanica-infra-db | RDS PostgreSQL (Terraform) |
| fiap-tc-mecanica-lambda | Auth CPF→JWT (AWS Lambda) |
