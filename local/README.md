# Desenvolvimento Local — Guia Completo

Stack completa rodando localmente com um único comando. Sem Java instalado, sem AWS, sem configuração de cluster.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Observação |
|-----------|--------------|------------|
| Docker Desktop | 4.x | Engine + Compose incluídos |
| Git | qualquer | para clonar os repos |
| Insomnia (ou Postman) | qualquer | para consumir as APIs |

---

## Estrutura de diretórios esperada

O `docker-compose.full.yml` referencia os outros repos com caminho relativo `../../mecanica-*`. Todos devem estar clonados na **mesma pasta pai**:

```
fiap-tc-mecanica/               ← workspace raiz (symlinks)
├── ms-infra-ms/                ← este repo
│   └── local/
│       ├── .env.example
│       ├── docker-compose.full.yml
│       └── docker-compose.infra.yml
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
# Permissão necessária: read:packages
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx

# Padrões funcionam para dev local
DB_USER=mecanica
DB_PASS=mecanica
RABBITMQ_USER=guest
RABBITMQ_PASS=guest

# OPCIONAL — token sandbox do Mercado Pago
# Sem ele, o billing-service falha na criação de preferência de pagamento.
# Use o endpoint /simular (descrito abaixo) como alternativa sem dependência externa.
# Criar em: https://www.mercadopago.com.br/developers → sua aplicação → Credenciais de teste
MP_ACCESS_TOKEN=APP_USR-xxxxxxxxxxxxxxxxxxxx
```

> **Por que GITHUB_TOKEN?** O `mecanica-shared-kernel:0.1.0` é publicado no GitHub Packages. O Docker build do Maven precisa autenticar para baixar a lib.

---

## Subindo a stack

```bash
docker compose -f docker-compose.full.yml up --build
```

Na **primeira execução** o build demora ~3-5 minutos (baixa imagens Maven + compila os 4 projetos). Nas seguintes é muito mais rápido (camadas em cache).

Aguarde até todos os serviços aparecerem como `healthy`:

```
mecanica-rabbitmq       ... healthy
mecanica-postgres-os    ... healthy
mecanica-postgres-billing ... healthy
mecanica-postgres-inventory ... healthy
mecanica-mongodb        ... healthy
mecanica-os-service     ... healthy
mecanica-billing-service ... healthy
mecanica-inventory-service ... healthy
mecanica-workshop-service ... healthy
```

### Modo só-infra (para desenvolvimento ativo)

Se preferir rodar os MS na sua máquina com `./mvnw spring-boot:run` (requer Java 21):

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

### Cliente e veículo de exemplo (os-service)

- **Cliente:** CPF 459.339.042-79
- **Veículo:** Toyota Corolla 2022 — placa `ABC1D23`
- **IDs fixos:** `clienteId = 00000000-0000-0000-0000-000000000010`, `veiculoId = 00000000-0000-0000-0000-000000000020`

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

### Passo 1 — Login

```
POST http://localhost:8080/api/auth/login
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

> O token tem validade de 24h e funciona em **todos os serviços** (os, billing, inventory, workshop) pois compartilham a mesma secret-key.

---

### Passo 2 — Abrir uma Ordem de Serviço

```
POST http://localhost:8080/api/ordens
Authorization: Bearer <token>
Content-Type: application/json

{
  "clienteId": "00000000-0000-0000-0000-000000000010",
  "veiculoId": "00000000-0000-0000-0000-000000000020",
  "descricaoProblema": "Carro fazendo barulho ao frear",
  "prioridade": "MEDIA"
}
```

**Resposta:** OS criada com `status: RECEBIDA`. Guarde o `id` (osId).

---

### Passo 3 — Adicionar itens à OS

Adicione as peças/insumos/serviços que serão usados no reparo. Use os UUIDs dos itens de seed do inventory-service:

```
POST http://localhost:8080/api/ordens/{osId}/itens
Authorization: Bearer <token>
Content-Type: application/json

{
  "tipo": "PECA",
  "referenciaId": "10000000-0000-0000-0000-000000000002",
  "descricao": "Pastilha de Freio Dianteira",
  "quantidade": 1,
  "valorUnitario": 189.90
}
```

Repita para cada item desejado.

---

### Passo 4 — Iniciar diagnóstico

```
POST http://localhost:8080/api/ordens/{osId}/diagnostico
Authorization: Bearer <token>
```

Status avança para `EM_DIAGNOSTICO`.

---

### Passo 5 — Emitir orçamento (dispara a Saga)

```
POST http://localhost:8080/api/ordens/{osId}/orcamento
Authorization: Bearer <token>
```

Neste momento:
- OS avança para `ORCAMENTO_EMITIDO`
- os-service publica `GerarOrcamentoCommand` no RabbitMQ
- billing-service recebe, calcula o orçamento e chama o Mercado Pago
- billing-service publica `OrcamentoCriadoEvent` com `orcamentoId` e `paymentUrl`
- Saga avança para `AGUARDANDO_PAGAMENTO`

Você pode acompanhar os logs em tempo real:
```bash
docker compose -f docker-compose.full.yml logs -f billing-service os-service
```

---

### Passo 6 — Consultar orçamento gerado

```
GET http://localhost:8081/api/billing/orcamentos?page=0&size=10
Authorization: Bearer <token>
```

Guarde o `id` do orçamento (`orcamentoId`).

---

### Passo 7 — Simular pagamento aprovado

Sem precisar de ngrok ou cartão real — chame o endpoint de simulação diretamente:

```
POST http://localhost:8081/api/billing/webhooks/simular
Content-Type: application/json

{
  "orcamentoId": "<orcamentoId>",
  "decisao": "APROVADO"
}
```

> Este endpoint **não exige autenticação** (equivale ao webhook que o Mercado Pago chamaria após pagamento real).

A partir daqui a Saga continua automaticamente via RabbitMQ:
1. billing-service publica `PagamentoConfirmadoEvent`
2. os-service aprova a OS → status `APROVADA`
3. os-service publica `ReservarPecasCommand`
4. inventory-service reserva as peças → publica `PecasReservadasEvent`
5. os-service inicia execução → publica `IniciarExecucaoCommand`
6. workshop-service atribui mecânico e executa reparo → publica `ExecucaoFinalizadaEvent`
7. os-service finaliza a OS → status `ENTREGUE`

---

### Passo 8 — Verificar OS finalizada

```
GET http://localhost:8080/api/ordens/{osId}
Authorization: Bearer <token>
```

A OS deve estar com `status: ENTREGUE`.

---

## Fluxo de compensação — Caminho triste (pagamento recusado)

Substitua o Passo 7 por:

```
POST http://localhost:8081/api/billing/webhooks/simular
Content-Type: application/json

{
  "orcamentoId": "<orcamentoId>",
  "decisao": "RECUSADO"
}
```

A Saga compensa: OS avança para `CANCELADA`.

---

## Interfaces de monitoramento

| Interface | URL | Credenciais |
|-----------|-----|------------|
| RabbitMQ Management | http://localhost:15672 | guest / guest |
| Swagger os-service | http://localhost:8080/swagger-ui.html | — |
| Swagger billing-service | http://localhost:8081/swagger-ui.html | — |
| Swagger inventory-service | http://localhost:8082/swagger-ui.html | — |
| Swagger workshop-service | http://localhost:8083/swagger-ui.html | — |

---

## Parar e limpar

```bash
# Parar mantendo volumes (dados persistidos entre reinicializações)
docker compose -f docker-compose.full.yml down

# Parar e apagar todos os dados (volta do zero)
docker compose -f docker-compose.full.yml down -v
```

---

## Solução de problemas

**Build falha com erro de autenticação no Maven**
→ O `GITHUB_TOKEN` no `.env` está errado ou sem permissão `read:packages`. Gere um novo PAT em github.com/settings/tokens.

**Serviço fica em `starting` por muito tempo**
→ Aguarde mais — o JVM demora ~60-90s para iniciar. Cheque os logs: `docker compose logs -f <nome-do-servico>`.

**`POST /api/auth/login` retorna 401**
→ O seeding ainda não rodou. Aguarde o os-service ficar `healthy` e tente novamente.

**Saga para em `AGUARDANDO_PAGAMENTO` e não avança**
→ Normal se `MP_ACCESS_TOKEN` for inválido — o billing-service falhou ao criar a preferência no MP. Use o endpoint `/simular` do Passo 7 para avançar manualmente, ou configure um token sandbox válido no `.env`.

**Porta já em uso**
→ Algum serviço local está usando a mesma porta. Pare o processo ou edite as portas no `docker-compose.full.yml`.
