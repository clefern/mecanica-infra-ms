# Desenvolvimento Local — Guia Completo

Stack completa rodando localmente com um único comando. Sem Java instalado, sem AWS, sem configuração de cluster.

**Ponto único de entrada:** `http://localhost` (porta 80) via Traefik — mesmo comportamento do cluster EKS.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Observação |
|-----------|--------------|------------|
| Docker Desktop | 4.x | Engine + Compose incluídos |
| Git | qualquer | para clonar os repos |
| jq | qualquer | para o smoke test (`brew install jq`) |
| Insomnia (ou Postman) | qualquer | para consumir as APIs manualmente |

---

## Estrutura de diretórios esperada

O `docker-compose.full.yml` referencia os outros repos com caminho relativo `../../ms-*`. Todos devem estar clonados na **mesma pasta pai**:

```
fiap-tc-mecanica/               ← workspace raiz
├── ms-infra-ms/                ← este repo
│   ├── mecanica-fiap/          ← você está aqui
│   │   ├── .env.example
│   │   ├── docker-compose.full.yml
│   │   └── docker-compose.infra.yml
│   └── scripts/
│       └── smoke-test.sh
├── ms-os-service/
├── ms-billing-service/
├── ms-inventory-service/
└── ms-workshop-service/
```

---

## Setup (uma vez)

### 1. Criar o `.env`

```bash
cp .env.example .env
```

Editar o `.env` com os valores reais:

```env
# OBRIGATÓRIO — PAT do GitHub com permissão read:packages
# Criar em: https://github.com/settings/tokens (classic)
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# Padrões funcionam para dev local (não precisa alterar)
DB_USER=mecanica
DB_PASS=mecanica
RABBITMQ_USER=guest
RABBITMQ_PASS=guest

# OPCIONAL — token sandbox do Mercado Pago
# Sem ele use o endpoint /simular (Passo 7) como alternativa
MP_ACCESS_TOKEN=APP_USR-xxxxxxxxxxxxxxxxxxxx

# NECESSÁRIO no macOS com Docker Desktop
# Descomentar e substituir <seu-usuario> pelo seu nome de usuário macOS
# DOCKER_SOCK=/Users/<seu-usuario>/.docker/run/docker.sock
```

> **Por que `GITHUB_TOKEN`?** O `mecanica-shared-kernel:0.1.0` é publicado no GitHub Packages. O build Maven precisa autenticar para baixar a lib.

> **Por que `DOCKER_SOCK` no macOS?** O Docker Desktop no macOS não cria `/var/run/docker.sock` — o socket fica em `~/.docker/run/docker.sock`. O Traefik precisa do socket para descobrir os containers automaticamente.

---

## Subindo a stack

```bash
docker compose -f docker-compose.full.yml up --build
```

Na **primeira execução** o build demora ~3–5 min (baixa imagens Maven + compila os 4 projetos). Nas seguintes é muito mais rápido (camadas em cache).

Aguarde todos os serviços aparecerem como `healthy` ou `Started`:

```
mecanica-traefik            ... Started
mecanica-rabbitmq           ... healthy
mecanica-postgres-os        ... healthy
mecanica-postgres-billing   ... healthy
mecanica-postgres-inventory ... healthy
mecanica-mongodb-workshop   ... healthy
mecanica-mailhog            ... Started
mecanica-adminer            ... Started
mecanica-mongo-express      ... Started
mecanica-os-service         ... Started   (~60–90s para o JVM iniciar)
mecanica-billing-service    ... Started
mecanica-inventory-service  ... Started
mecanica-workshop-service   ... Started
```

### Modo só-infra (desenvolvimento ativo)

Para rodar os MS na sua máquina com `./mvnw spring-boot:run` (requer Java 21):

```bash
docker compose -f docker-compose.infra.yml up -d
```

---

## Dados de seed (criados automaticamente na inicialização)

### Usuários (os-service)

| Email | Senha | Role |
|-------|-------|------|
| admin@mecanica.com | 123456 | ADMIN |
| mecanico@mecanica.com | 123456 | MECANICO |
| atendente@mecanica.com | 123456 | ATENDENTE |
| cliente@mecanica.com | 123456 | CLIENTE |

### Cliente, veículo e mecânico de exemplo (os-service)

- **Cliente:** CPF 459.339.042-79 — `clienteId = 00000000-0000-0000-0000-000000000010`
- **Veículo:** Toyota Corolla 2022 placa `ABC1D23` — `veiculoId = 00000000-0000-0000-0000-000000000020`
- **Mecânico:** `mecanicoId = 00000000-0000-0000-0000-000000000002`

### Itens de estoque (inventory-service)

| UUID | Tipo | Item | Preço |
|------|------|------|-------|
| 10000000-0000-0000-0000-000000000001 | PECA | Filtro de Óleo | R$ 45,90 |
| 10000000-0000-0000-0000-000000000002 | PECA | Pastilha de Freio Dianteira | R$ 189,90 |
| 10000000-0000-0000-0000-000000000003 | PECA | Correia Dentada | R$ 320,00 |
| 10000000-0000-0000-0000-000000000011 | INSUMO | Óleo de Motor 5W30 | R$ 65,00 |
| 10000000-0000-0000-0000-000000000012 | INSUMO | Fluido de Freio DOT4 | R$ 28,50 |

---

## Fluxo completo via Insomnia — Caminho feliz (Saga aprovada)

> Todos os exemplos usam `http://localhost` (Traefik porta 80). As portas diretas `localhost:8080`, `localhost:8081` etc. também funcionam caso prefira acessar cada serviço diretamente.

### Passo 1 — Login

```
POST http://localhost/api/auth/login
Content-Type: application/json

{
  "email": "admin@mecanica.com",
  "password": "123456"
}
```

**Resposta:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer"
}
```

Salve o `accessToken`. Todas as chamadas seguintes usam:
```
Authorization: Bearer <accessToken>
```

> O token tem validade de 24h e funciona em **todos os serviços** — eles compartilham a mesma `SECURITY_JWT_SECRET_KEY`.

---

### Passo 2 — Abrir uma Ordem de Serviço

```
POST http://localhost/api/ordens-servico
Authorization: Bearer <token>
Content-Type: application/json

{
  "clienteId": "00000000-0000-0000-0000-000000000010",
  "veiculoId":  "00000000-0000-0000-0000-000000000020",
  "mecanicoId": "00000000-0000-0000-0000-000000000002"
}
```

**Resposta:** OS criada com `status: RECEBIDA`. Guarde o `id` (osId).

---

### Passo 3 — Adicionar itens à OS

```
POST http://localhost/api/ordens-servico/{osId}/itens
Authorization: Bearer <token>
Content-Type: application/json

{
  "referenciaId": "10000000-0000-0000-0000-000000000002",
  "tipo": "PECA",
  "descricao": "Pastilha de Freio Dianteira",
  "valorUnitario": 189.90,
  "quantidade": 1
}
```

Repita para cada item. O campo `referenciaId` deve ser um UUID da tabela de estoque acima.

---

### Passo 4 — Iniciar diagnóstico

```
PUT http://localhost/api/ordens-servico/{osId}/iniciar-diagnostico
Authorization: Bearer <token>
```

Status avança para `EM_DIAGNOSTICO`.

---

### Passo 5 — Emitir orçamento (dispara a Saga)

```
PUT http://localhost/api/ordens-servico/{osId}/emitir-orcamento
Authorization: Bearer <token>
```

Neste momento a Saga começa:
- OS → `AGUARDANDO_APROVACAO`
- os-service publica `GerarOrcamentoCommand` no RabbitMQ
- billing-service cria o orçamento e chama o Mercado Pago (ou usa placeholder sem token real)
- billing-service publica `OrcamentoCriadoEvent`

Acompanhe em tempo real:
```bash
docker compose -f docker-compose.full.yml logs -f os-service billing-service
```

---

### Passo 6 — Consultar orçamento gerado

```
GET http://localhost/api/billing/orcamentos?page=0&size=10
Authorization: Bearer <token>
```

Guarde o `id` do orçamento (`orcamentoId`).

---

### Passo 7 — Simular pagamento aprovado

Sem ngrok ou cartão real — endpoint de simulação local:

```
POST http://localhost/api/billing/webhooks/simular
Content-Type: application/json

{
  "orcamentoId": "<orcamentoId>",
  "decisao": "APROVADO"
}
```

> Este endpoint **não exige autenticação** (equivale ao webhook do Mercado Pago após pagamento real).

A partir daqui a Saga conclui automaticamente via RabbitMQ:

1. billing → `PagamentoConfirmadoEvent`
2. os-service aprova OS → `APROVADA` → publica `ReservarPecasCommand`
3. inventory-service reserva peças → `PecasReservadasEvent`
4. os-service inicia execução → `EM_EXECUCAO` → publica `IniciarExecucaoCommand`
5. workshop-service executa reparo → `ExecucaoFinalizadaEvent`
6. os-service finaliza → `ENTREGUE`

---

### Passo 8 — Verificar OS finalizada

```
GET http://localhost/api/ordens-servico/{osId}
Authorization: Bearer <token>
```

A OS deve estar com `"status": "ENTREGUE"`.

---

## Fluxo de compensação — Pagamento recusado

Substitua o Passo 7 por:

```
POST http://localhost/api/billing/webhooks/simular
Content-Type: application/json

{
  "orcamentoId": "<orcamentoId>",
  "decisao": "RECUSADO"
}
```

A Saga compensa: OS avança para `CANCELADA`.

---

## Smoke test automatizado

Valida o fluxo completo end-to-end com um único comando (requer `jq`):

```bash
# Via portas diretas (padrão)
bash ../scripts/smoke-test.sh

# Via Traefik (porta 80) — mesmo comportamento do cluster
OS_PORT=80 BILLING_PORT=80 bash ../scripts/smoke-test.sh
```

Saída esperada:
```
[OK] Login OK — token obtido
[OK] OS criada — id=... status=RECEBIDA
[OK] Item adicionado
[OK] Diagnóstico iniciado
[OK] Orçamento emitido — Saga iniciada
[OK] Orçamento criado — orcamentoId=...
[OK] Pagamento simulado
[OK] OS finalizada — status=ENTREGUE
========================================
 SMOKE TEST PASSOU — Saga completa OK
========================================
```

---

## Interfaces de monitoramento

| Interface | URL | Credenciais / Observação |
|-----------|-----|--------------------------|
| **Gateway (Traefik dashboard)** | http://localhost:8099 | Visualiza rotas e serviços descobertos automaticamente |
| **RabbitMQ Management** | http://localhost:15672 | guest / guest — monitora filas e mensagens |
| **Adminer (Postgres)** | http://localhost:9090 | user: `mecanica` · pass: `mecanica` · Server: `postgres-os`, `postgres-billing` ou `postgres-inventory` |
| **mongo-express (MongoDB)** | http://localhost:8084 | Sem login — acesso direto ao `workshop_service` |
| **Mailhog (e-mail)** | http://localhost:8025 | Captura e-mails enviados pelo SMTP local (porta 1025) |
| Swagger os-service | http://localhost:8080/swagger-ui.html | — |
| Swagger billing-service | http://localhost:8081/swagger-ui.html | — |
| Swagger inventory-service | http://localhost:8082/swagger-ui.html | — |
| Swagger workshop-service | http://localhost:8083/swagger-ui.html | — |

> **Adminer — como trocar de banco:** no formulário de login, altere o campo "Server" para `postgres-billing` (porta 5433) ou `postgres-inventory` (porta 5434). O usuário e senha são sempre `mecanica`.

---

## Parar e limpar

```bash
# Parar mantendo volumes (dados persistidos entre reinicializações)
docker compose -f docker-compose.full.yml down

# Parar e apagar todos os dados (começa do zero)
docker compose -f docker-compose.full.yml down -v
```

---

## Solução de problemas

**Build falha com erro de autenticação no Maven**
→ `GITHUB_TOKEN` no `.env` está errado ou sem permissão `read:packages`. Gere um novo PAT em github.com/settings/tokens (classic) com escopo `read:packages`.

**Serviço fica em `starting` por muito tempo**
→ O JVM demora ~60–90s para iniciar. Aguarde e verifique: `docker compose logs -f <nome-do-servico>`.

**`POST /api/auth/login` retorna 401**
→ O seed ainda não rodou. Aguarde o os-service ficar `healthy` e tente novamente.

**Saga para em `APROVADA` e não avança para `EM_EXECUCAO`**
→ Certifique-se de que o campo `mecanicoId` foi enviado na criação da OS (Passo 2). Sem ele, a transição de `APROVADA` para execução lança exceção.

**Traefik não roteia / retorna 404**
→ No macOS, verifique se `DOCKER_SOCK` está configurado no `.env` apontando para `~/.docker/run/docker.sock`. Confirme com: `docker logs mecanica-traefik`.

**Porta já em uso**
→ Verifique processos locais: `lsof -i :<porta>`. Pare o processo ou ajuste as portas no `docker-compose.full.yml`.
