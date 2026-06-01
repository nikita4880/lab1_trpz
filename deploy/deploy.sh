#!/usr/bin/env bash
# deploy.sh — розгортання на target node
set -euo pipefail

IMAGE="${IMAGE:?IMAGE is required}"
DB_NAME="${DB_NAME:?DB_NAME is required}"
DB_USER="${DB_USER:?DB_USER is required}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
APP_PORT="${APP_PORT:-8000}"

echo "==> Розгортання образу: ${IMAGE}"

echo "==> [1/3] Завантаження образу"
docker pull "${IMAGE}"

echo "==> [2/3] Запуск міграції"
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  --entrypoint python \
  "${IMAGE}" migrate.py \
    --db-host host.docker.internal \
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
  --add-host=host.docker.internal:host-gateway \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=3306 \
  -e DB_NAME="${DB_NAME}" \
  -e DB_USER="${DB_USER}" \
  -e DB_PASSWORD="${DB_PASSWORD}" \
  "${IMAGE}" \
  --host 0.0.0.0 \
  --port "${APP_PORT}" \
  --db-host host.docker.internal \
  --db-name "${DB_NAME}" \
  --db-user "${DB_USER}" \
  --db-password "${DB_PASSWORD}"

docker ps --filter name=mywebapp
echo "✅ Розгортання завершено: ${IMAGE}"
