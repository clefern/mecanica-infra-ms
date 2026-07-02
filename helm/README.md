# helm — Charts de Infraestrutura (Fase 4)

Helm charts para RabbitMQ e MongoDB no cluster EKS (namespace `mecanica-ms`).

## Estrutura

```
helm/
├── rabbitmq/
│   ├── Chart.yaml    ← wrapper bitnami/rabbitmq 14.x
│   └── values.yaml   ← credenciais, recursos, persistência
└── mongodb/
    ├── Chart.yaml    ← wrapper bitnami/mongodb 16.x
    └── values.yaml   ← sem auth, WiredTiger 0.5GB, init collections
```

## Pré-requisitos

```bash
# Adicionar repositório Bitnami (uma vez)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

## Deploy no EKS

### RabbitMQ

```bash
cd helm/rabbitmq/

# Baixar dependências
helm dependency update

# Instalar (primeira vez)
helm install mecanica-rabbitmq . \
  --namespace mecanica-ms \
  --create-namespace \
  -f values.yaml

# Atualizar
helm upgrade mecanica-rabbitmq . \
  --namespace mecanica-ms \
  -f values.yaml
```

Verificar:
```bash
kubectl get pods -n mecanica-ms -l app.kubernetes.io/name=rabbitmq
kubectl port-forward svc/mecanica-rabbitmq 15672:15672 -n mecanica-ms
# http://localhost:15672  (guest/guest)
```

### MongoDB

```bash
cd helm/mongodb/

# Baixar dependências
helm dependency update

# Instalar
helm install mecanica-mongodb . \
  --namespace mecanica-ms \
  --create-namespace \
  -f values.yaml

# Atualizar
helm upgrade mecanica-mongodb . \
  --namespace mecanica-ms \
  -f values.yaml
```

Verificar:
```bash
kubectl get pods -n mecanica-ms -l app.kubernetes.io/name=mongodb
kubectl port-forward svc/mecanica-mongodb 27017:27017 -n mecanica-ms
```

## Connection strings para os MS

Depois do deploy, o `workshop-service` aponta para:

```
MONGODB_URI=mongodb://mecanica-mongodb.mecanica-ms.svc.cluster.local:27017/workshop_service
```

E os MS apontam para RabbitMQ:

```
RABBITMQ_HOST=mecanica-rabbitmq.mecanica-ms.svc.cluster.local
RABBITMQ_USER=guest
RABBITMQ_PASS=guest
```

## Listar releases

```bash
helm list -n mecanica-ms
```
