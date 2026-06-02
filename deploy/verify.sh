#!/usr/bin/env bash
# verify.sh — верифікація розгортання на target node
# Перевіряє: доступність сервісу, коректність nginx, health-ендпоінти

set -euo pipefail

TARGET_URL="${TARGET_URL:-http://localhost}"
APP_PORT="${APP_PORT:-8000}"
FAILURES=0

pass() { echo "  ✅ $*"; }
fail() { echo "  ❌ $*"; FAILURES=$((FAILURES + 1)); }

echo ""
echo "══════════════════════════════════════════"
echo "  Верифікація розгортання mywebapp"
echo "══════════════════════════════════════════"

# ── 1. systemd-сервіс активний ────────────────────────────────
echo ""
echo "[1] systemd-сервіс mywebapp"
if docker ps --filter "name=mywebapp" --filter "status=running" | grep -q mywebapp; then
  pass "mywebapp.service is active"
else
  fail "mywebapp.service is NOT active"
  systemctl status mywebapp --no-pager || true
fi

# ── 2. Контейнер запущений ────────────────────────────────────
echo ""
echo "[2] Docker-контейнер"
if docker ps --filter "name=mywebapp" --filter "status=running" | grep -q mywebapp; then
  pass "Container 'mywebapp' is running"
else
  fail "Container 'mywebapp' is NOT running"
  docker ps -a --filter "name=mywebapp" || true
fi

# ── 3. /health/alive — прямо на застосунок ────────────────────
echo ""
echo "[3] GET /health/alive (прямо, порт ${APP_PORT})"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:${APP_PORT}/health/alive" || echo "000")
if [ "$STATUS" = "200" ]; then
  pass "/health/alive → HTTP 200"
else
  fail "/health/alive → HTTP ${STATUS} (очікувалось 200)"
fi

# ── 4. /health/ready — БД доступна ───────────────────────────
echo ""
echo "[4] GET /health/ready (прямо, порт ${APP_PORT})"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://127.0.0.1:${APP_PORT}/health/ready" || echo "000")
if [ "$STATUS" = "200" ]; then
  pass "/health/ready → HTTP 200 (БД доступна)"
else
  fail "/health/ready → HTTP ${STATUS} (БД недоступна або сервіс не готовий)"
fi

# ── 5. Nginx проксіює запити ──────────────────────────────────
echo ""
echo "[5] Nginx reverse proxy — GET / через порт 80"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${TARGET_URL}/" || echo "000")
if [ "$STATUS" = "200" ]; then
  pass "Nginx → HTTP 200 (proxy працює)"
else
  fail "Nginx → HTTP ${STATUS} (очікувалось 200)"
fi

# ── 6. Nginx закриває /health/ зовні ─────────────────────────
echo ""
echo "[6] Nginx — /health/ закритий зовні (403)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "${TARGET_URL}/health/alive" || echo "000")
if [ "$STATUS" = "403" ]; then
  pass "/health/alive через nginx → HTTP 403 (правильно закритий)"
else
  fail "/health/alive через nginx → HTTP ${STATUS} (очікувалось 403)"
fi

# ── 7. GET /items повертає JSON ───────────────────────────────
echo ""
echo "[7] GET /items → JSON"
BODY=$(curl -s -H "Accept: application/json" \
  "${TARGET_URL}/items" || echo "ERROR")
if echo "$BODY" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  pass "/items → валідний JSON"
else
  fail "/items → невалідна відповідь: ${BODY}"
fi

# ── 8. POST /items → 201 ─────────────────────────────────────
echo ""
echo "[8] POST /items → 201 Created"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${TARGET_URL}/items" \
  -H "Content-Type: application/json" \
  -d '{"name":"verify-test-item","quantity":1}' || echo "000")
if [ "$STATUS" = "201" ]; then
  pass "POST /items → HTTP 201 Created"
else
  fail "POST /items → HTTP ${STATUS} (очікувалось 201)"
fi

# ── Підсумок ──────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
if [ "$FAILURES" -eq 0 ]; then
  echo "  ✅ Верифікація ПРОЙШЛА (0 помилок)"
  echo "══════════════════════════════════════════"
  exit 0
else
  echo "  ❌ Верифікація ПРОВАЛЕНА (${FAILURES} помилок)"
  echo "══════════════════════════════════════════"
  exit 1
fi
