#!/usr/bin/env bash
# deploy.sh — розгортання на target node
set -euo pipefail

IMAGE="${IMAGE:?IMAGE is required}"
DB_NAME="${DB_NAME:?DB_NAME is required}"
DB_USER="${DB_USER:?DB_USER is required}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
APP_PORT="${APP_PORT:-8000}"
DB_HOST="${DB_HOST:-172.17.0.1}"

echo "==> Розгортання образу: ${IMAGE}"

echo "==> [1/3] Завантаження образу"
docker pull "${IMAGE}"

echo "==> [2/3] Запуск міграції"
docker run --rm \
  -e DB_HOST="${DB_HOST}" \
  -e DB_PORT=3306 \
  -e DB_NAME="${DB_NAME}" \
  -e DB_USER="${DB_USER}" \
  -e DB_PASSWORD="${DB_PASSWORD}" \
  --entrypoint python \
  "${IMAGE}" migrate.py \
    --db-host "${DB_HOST}" \
    --db-name "${DB_NAME}" \
    --db-user "${DB_USER}" \
    --db-password "${DB_PASSWORD}"

echo "==> [3/3] Перезапуск контейнера"
docker stop mywebapp 2>/dev/null || true
docker rm mywebapp 2>/dev/null || true
docker run -d \
  --name mywebapp \
  --restart unless-stopped \
  -p 127.0.0.1:${APP_PORT}:${APP_PORT} \
  -e DB_HOST="${DB_HOST}" \
  -e DB_PORT=3306 \
  -e DB_NAME="${DB_NAME}" \
  -e DB_USER="${DB_USER}" \
  -e DB_PASSWORD="${DB_PASSWORD}" \
  "${IMAGE}" \
  --host 0.0.0.0 \
  --port "${APP_PORT}" \
  --db-host "${DB_HOST}" \
  --db-name "${DB_NAME}" \
  --db-user "${DB_USER}" \
  --db-password "${DB_PASSWORD}"

docker ps --filter name=mywebapp
echo "Розгортання завершено: ${IMAGE}"
