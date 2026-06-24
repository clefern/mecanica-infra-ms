# mecanica-infra-ms

Infraestrutura dos microsserviços da **Fase 4 — Mecânica API** (Grupo 14SOAT).

## Desenvolvimento local

### Pré-requisito único: Docker Desktop

#### Modo 1 — Só infra (recomendado para dev ativo)
Sobe RabbitMQ + 3× PostgreSQL + MongoDB. Os serviços rodam na máquina com `./mvnw spring-boot:run` (requer Java 21).

```bash
cd local/
docker compose -f docker-compose.infra.yml up -d
```

Portas:
| Serviço | Porta |
|---------|-------|
| RabbitMQ AMQP | 5672 |
| RabbitMQ Management UI | 15672 |
| PostgreSQL (os-service) | 5432 |
| PostgreSQL (billing-service) | 5433 |
| PostgreSQL (inventory-service) | 5434 |
| MongoDB (workshop-service) | 27017 |

#### Modo 2 — Stack completo (zero install)
Builda e sobe os 4 serviços + toda a infra. Não requer Java na máquina.

```bash
# 1. Copiar e preencher o .env
cp local/.env.example local/.env
# Editar .env: GITHUB_TOKEN=ghp_seu_token (read:packages)

# 2. Garantir que os repos estão clonados em /Volumes/Workspace/
# mecanica-os-service, mecanica-billing-service,
# mecanica-inventory-service, mecanica-workshop-service

# 3. Subir
cd local/
docker compose -f docker-compose.full.yml up --build
```

Portas dos serviços: os=8080, billing=8081, inventory=8082, workshop=8083.

> **Por que GITHUB_TOKEN?** O `mecanica-shared-kernel:0.1.0` é publicado no GitHub Packages. Durante o `docker build`, o Maven precisa autenticar para baixar a lib. Use um PAT com permissão `read:packages`.

## Estrutura

```
local/          ← docker-compose para dev local
k8s/            ← manifestos Kubernetes (Frente B)
helm/           ← Helm charts: RabbitMQ, MongoDB (Frente B)
```
