#!/usr/bin/env bash
# setup_target.sh — налаштування target node (Ubuntu 24.04)
# Запуск: sudo bash setup_target.sh
# Встановлює: Docker, MariaDB, Nginx
# Створює БД, користувача, налаштовує nginx як reverse proxy

set -euo pipefail

DB_NAME="${DB_NAME:-mywebapp}"
DB_USER="${DB_USER:-mywebapp}"
DB_PASSWORD="${DB_PASSWORD:-mywebapp_pass}"
APP_PORT="${APP_PORT:-8000}"

echo "==> [1/6] Оновлення системи"
apt-get update -q
apt-get upgrade -y -q

echo "==> [2/6] Встановлення Docker"
apt-get install -y -q ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker
usermod -aG docker "${SUDO_USER:-ubuntu}"

echo "==> [3/6] Встановлення MariaDB"
apt-get install -y -q mariadb-server

systemctl enable --now mariadb

echo "==> [4/6] Налаштування БД"
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'172.17.0.0/255.255.0.0'
  IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
  IDENTIFIED BY '${DB_PASSWORD}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'172.17.0.0/255.255.0.0';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# Дозволяємо підключення з Docker-мережі
sed -i 's/bind-address\s*=\s*127\.0\.0\.1/bind-address = 0.0.0.0/' \
  /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null || true

systemctl restart mariadb

echo "==> [5/6] Встановлення та налаштування Nginx"
apt-get install -y -q nginx

cat > /etc/nginx/sites-available/mywebapp <<NGINX
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/mywebapp_access.log;
    error_log  /var/log/nginx/mywebapp_error.log;

    location /health/ {
        deny all;
        return 403;
    }

    location / {
        proxy_pass         http://127.0.0.1:${APP_PORT};
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx

echo "==> [6/6] Налаштування systemd-юніту для контейнера"
cat > /etc/systemd/system/mywebapp.service <<UNIT
[Unit]
Description=mywebapp container
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5s

# Змінні передаються через /etc/mywebapp.env (не в репозиторії!)
EnvironmentFile=/etc/mywebapp.env

ExecStartPre=-/usr/bin/docker stop mywebapp
ExecStartPre=-/usr/bin/docker rm   mywebapp
ExecStart=/usr/bin/docker run --rm \
    --name mywebapp \
    -p 127.0.0.1:${APP_PORT}:${APP_PORT} \
    --add-host=host.docker.internal:host-gateway \
    --env-file /etc/mywebapp.env \
    \${IMAGE}

ExecStop=/usr/bin/docker stop mywebapp

[Install]
WantedBy=multi-user.target
UNIT

# Шаблон env-файлу (без паролів — заповнюється вручну або через CD)
if [ ! -f /etc/mywebapp.env ]; then
  cat > /etc/mywebapp.env <<ENV
IMAGE=ghcr.io/nikita4880/lab1_trpz:stable
DB_HOST=host.docker.internal
DB_PORT=3306
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
APP_PORT=${APP_PORT}
ENV
  chmod 600 /etc/mywebapp.env
fi

systemctl daemon-reload
systemctl enable mywebapp

echo ""
echo "✅ Target node налаштований!"
echo "   БД:    ${DB_NAME} / ${DB_USER}"
echo "   Порт:  ${APP_PORT}"
echo "   Nginx: http://localhost"
echo ""
echo "Після першого деплою запустити:"
echo "   sudo systemctl start mywebapp"
