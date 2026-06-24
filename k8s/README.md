# k8s — Manifestos Kubernetes dos Microsserviços

> Frente B (Gabriel + Cristian) — a preencher.

Estrutura esperada:
```
k8s/
├── base/
│   ├── rabbitmq/          ← HelmRelease ou Deployment do RabbitMQ
│   ├── os-service/        ← Deployment, Service, IngressRoute
│   ├── billing-service/
│   ├── inventory-service/
│   └── workshop-service/
└── overlays/
    ├── dev/
    └── prod/
```

Referência: `infra-k8s/k8s/` da Fase 3 para padrão de Kustomize + Traefik IngressRoute.
