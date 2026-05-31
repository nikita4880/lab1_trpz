#!/usr/bin/env bash
# deploy.sh — розгортання нової версії застосунку на target node
# Запускається з runner через SSH
# Змінні середовища: IMAGE, DB_NAME, DB_USER, DB_PASSWORD

set -euo pipefail

IMAGE="${IMAGE:?IMAGE is required}"
DB_NAME="${DB_NAME:?DB_NAME is required}"
DB_USER="${DB_USER:?DB_USER is required}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD is required}"
APP_PORT="${APP_PORT:-8000}"

echo "==> Розгортання образу: ${IMAGE}"

echo "==> [1/4] Оновлення /etc/mywebapp.env"
sudo tee /etc/mywebapp.env > /dev/null <<ENV
IMAGE=${IMAGE}
DB_HOST=host.docker.internal
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
APP_PORT=${APP_PORT}
ENV
sudo chmod 600 /etc/mywebapp.env

echo "==> [2/4] Завантаження нового образу"
sudo docker pull "${IMAGE}"

echo "==> [3/4] Запуск міграції БД"
sudo docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  --env DB_HOST=host.docker.internal \
  --env DB_PORT=3306 \
  --env DB_NAME="${DB_NAME}" \
  --env DB_USER="${DB_USER}" \
  --env DB_PASSWORD="${DB_PASSWORD}" \
  --entrypoint python \
  "${IMAGE}" migrate.py \
    --db-host host.docker.internal \
    --db-name "${DB_NAME}" \
    --db-user "${DB_USER}" \
    --db-password "${DB_PASSWORD}"

echo "==> [4/4] Перезапуск systemd-сервісу"
sudo systemctl restart mywebapp
sudo systemctl is-active mywebapp

echo "✅ Розгортання завершено: ${IMAGE}"
