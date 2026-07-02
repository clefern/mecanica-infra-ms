#!/usr/bin/env bash
# Smoke test — valida o fluxo completo da Saga localmente ou no cluster.
#
# Uso:
#   ./scripts/smoke-test.sh                        # local (padrão)
#   OS_BASE=http://meu-lb OS_PORT=80 ./scripts/smoke-test.sh  # cluster
#
# Dependências: curl, jq

set -euo pipefail

OS_BASE="${OS_BASE:-http://localhost}"
OS_PORT="${OS_PORT:-8080}"
BILLING_BASE="${BILLING_BASE:-http://localhost}"
BILLING_PORT="${BILLING_PORT:-8081}"

OS_URL="$OS_BASE:$OS_PORT"
BILLING_URL="$BILLING_BASE:$BILLING_PORT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}[--]${NC} $1"; }

# ─── 1. Login ────────────────────────────────────────────────────────────────
info "1. Login como admin..."
LOGIN=$(curl -sf -X POST "$OS_URL/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@mecanica.com","password":"123456"}') \
  || fail "POST /api/auth/login falhou — os-service está rodando?"

TOKEN=$(echo "$LOGIN" | jq -r '.accessToken')
[ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] || fail "accessToken não retornado"
pass "Login OK — token obtido"

AUTH="Authorization: Bearer $TOKEN"

# ─── 2. Criar OS ─────────────────────────────────────────────────────────────
info "2. Criando Ordem de Serviço..."
OS=$(curl -sf -X POST "$OS_URL/api/ordens-servico" \
  -H "Content-Type: application/json" \
  -H "$AUTH" \
  -d '{
    "clienteId": "00000000-0000-0000-0000-000000000010",
    "veiculoId": "00000000-0000-0000-0000-000000000020",
    "mecanicoId": "00000000-0000-0000-0000-000000000002"
  }') || fail "POST /api/ordens-servico falhou"

OS_ID=$(echo "$OS" | jq -r '.id')
OS_STATUS=$(echo "$OS" | jq -r '.status')
[ "$OS_ID" != "null" ] || fail "OS criada sem id"
pass "OS criada — id=$OS_ID status=$OS_STATUS"

# ─── 3. Adicionar item ────────────────────────────────────────────────────────
info "3. Adicionando item à OS..."
curl -sf -X POST "$OS_URL/api/ordens-servico/$OS_ID/itens" \
  -H "Content-Type: application/json" \
  -H "$AUTH" \
  -d '{
    "referenciaId": "10000000-0000-0000-0000-000000000001",
    "tipo": "PECA",
    "descricao": "Filtro de Óleo",
    "valorUnitario": 45.90,
    "quantidade": 1
  }' > /dev/null || fail "POST /api/ordens-servico/$OS_ID/itens falhou"
pass "Item adicionado"

# ─── 4. Iniciar diagnóstico ───────────────────────────────────────────────────
info "4. Iniciando diagnóstico..."
curl -sf -X PUT "$OS_URL/api/ordens-servico/$OS_ID/iniciar-diagnostico" \
  -H "$AUTH" > /dev/null || fail "PUT /api/ordens-servico/$OS_ID/iniciar-diagnostico falhou"
pass "Diagnóstico iniciado"

# ─── 5. Emitir orçamento (dispara Saga) ──────────────────────────────────────
info "5. Emitindo orçamento (dispara Saga)..."
curl -sf -X PUT "$OS_URL/api/ordens-servico/$OS_ID/emitir-orcamento" \
  -H "$AUTH" > /dev/null || fail "PUT /api/ordens-servico/$OS_ID/emitir-orcamento falhou"
pass "Orçamento emitido — Saga iniciada"

# ─── 6. Aguardar orçamento no billing ────────────────────────────────────────
info "6. Aguardando billing-service criar orçamento (max 20s)..."
ORC_ID=""
for i in $(seq 1 20); do
  ORC_ID=$(curl -sf "$BILLING_URL/api/billing/orcamentos?page=0&size=50" \
    -H "$AUTH" | jq -r --arg osid "$OS_ID" \
    '.content[] | select(.osId == $osid) | .id' 2>/dev/null | head -1)
  [ -n "$ORC_ID" ] && break
  sleep 1
done
[ -n "$ORC_ID" ] || fail "Orçamento não criado no billing-service em 20s — verifique os logs"
pass "Orçamento criado — orcamentoId=$ORC_ID"

# ─── 7. Simular pagamento aprovado ───────────────────────────────────────────
info "7. Simulando pagamento aprovado..."
curl -sf -X POST "$BILLING_URL/api/billing/webhooks/simular" \
  -H "Content-Type: application/json" \
  -d "{\"orcamentoId\":\"$ORC_ID\",\"decisao\":\"APROVADO\"}" \
  > /dev/null || fail "POST /api/billing/webhooks/simular falhou"
pass "Pagamento simulado"

# ─── 8. Aguardar OS finalizada ────────────────────────────────────────────────
info "8. Aguardando Saga finalizar OS (max 30s)..."
FINAL_STATUS=""
for i in $(seq 1 30); do
  FINAL_STATUS=$(curl -sf "$OS_URL/api/ordens-servico/$OS_ID" \
    -H "$AUTH" | jq -r '.status' 2>/dev/null)
  [ "$FINAL_STATUS" = "ENTREGUE" ] && break
  sleep 1
done

if [ "$FINAL_STATUS" = "ENTREGUE" ]; then
  pass "OS finalizada — status=ENTREGUE"
  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN} SMOKE TEST PASSOU — Saga completa OK  ${NC}"
  echo -e "${GREEN}========================================${NC}"
else
  fail "OS não finalizou em 30s — status atual=$FINAL_STATUS. Verifique: docker compose logs -f"
fi
