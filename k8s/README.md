# k8s — Manifestos Kubernetes dos Microsserviços

Deploy dos 4 microsserviços da Fase 4 no cluster EKS (namespace `mecanica-ms`),
via Traefik IngressRoute como ponto único de entrada.

## Arquivos

```
k8s/
├── namespace.yaml          Namespace mecanica-ms
├── os-service.yaml         Deployment + Service (orquestrador da Saga)
├── billing-service.yaml    Deployment + Service (orçamento + Mercado Pago)
├── inventory-service.yaml  Deployment + Service (estoque/peças)
├── workshop-service.yaml   Deployment + Service (execução — MongoDB)
├── ms-ingressroute.yaml    Traefik IngressRoute (gateway /api/*)
├── kustomization.yaml      Agrega os manifestos acima
├── db-init-job.yaml        Job idempotente que cria os bancos por MS no RDS
└── secrets-setup.sh        Cria os K8s Secrets (credenciais RDS/Rabbit/JWT/…)
```

## Topologia de dados

Requisito da Fase 4: cada microsserviço com seu próprio banco de dados. Para
manter o bootstrap barato e simples num ambiente **AWS Academy limitado**:

| Serviço | Banco | Onde |
|---------|-------|------|
| os-service | `os_service` | RDS PostgreSQL (instância compartilhada) |
| billing-service | `billing_service` | RDS PostgreSQL (mesma instância) |
| inventory-service | `inventory_service` | RDS PostgreSQL (mesma instância) |
| workshop-service | `workshop_service` | MongoDB in-cluster (Helm `mecanica-mongodb`) |

Os 3 bancos SQL são **bancos lógicos isolados** numa única instância RDS
`db.t3.small` (provisionada por `fiap-tc-mecanica-infra-db`). Isolamento por
banco + credenciais, sem o custo de 3 instâncias. O `db-init-job` cria os bancos
de dentro do cluster porque o RDS não é público (`publicly_accessible = false`).

## Pré-requisitos

- `kubectl` apontando para o cluster (`aws eks update-kubeconfig --name lab-fiap-cluster`)
- RDS provisionado (`fiap-tc-mecanica-infra-db`) — anote host, usuário e senha
- RabbitMQ e MongoDB in-cluster (ver [`../helm/README.md`](../helm/README.md))

## Deploy

```bash
# 1. Manifestos (namespace, deployments, services, ingressroute)
kubectl apply -k k8s/

# 2. Secrets — editar os <placeholder> em secrets-setup.sh antes de rodar
bash k8s/secrets-setup.sh

# 3. Criar os bancos por MS no RDS (idempotente)
kubectl apply -f k8s/db-init-job.yaml
kubectl -n mecanica-ms wait --for=condition=complete job/db-init --timeout=120s
kubectl -n mecanica-ms logs job/db-init

# 4. Verificar
kubectl get pods -n mecanica-ms
```

As imagens nos Deployments são `placeholder:latest`; o `cd.yml` de cada serviço
(via `workflow_dispatch`) faz build → push ECR → `kubectl set image` para trocar
pela imagem real.

## Recriar os bancos

Jobs são imutáveis — para re-executar o bootstrap dos bancos:

```bash
kubectl -n mecanica-ms delete job db-init
kubectl apply -f k8s/db-init-job.yaml
```
