#!/usr/bin/env bash
set -eo pipefail

N=8
APP_DIR=/opt/mywebapp
DB_NAME=mywebapp
DB_USER=mywebapp
DB_PASSWORD="$(openssl rand -hex 16)"

echo "============================================"
echo " mywebapp installer  (N=$N)"
echo "============================================"

echo "[1/9] Встановлення пакетів..."
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv mariadb-server nginx openssl curl

echo "[2/9] Створення користувачів..."

create_user() {
    local u="$1"
    local p="$2"
    local g="$3"
    if ! id "$u" &>/dev/null; then
        useradd -m -s /bin/bash "$u"
    fi
    echo "$u:$p" | chpasswd
    if [ -n "$g" ]; then
        usermod -aG "$g" "$u" || true
    fi
    chage -d 0 "$u" 2>/dev/null || true
}

create_user student "student_pass_changeme" "sudo"
create_user teacher "12345678" "sudo"
create_user operator "12345678" ""

if ! id mywebapp &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$APP_DIR" mywebapp
fi

echo "[3/9] Налаштування sudo для operator..."
cat > /etc/sudoers.d/operator << 'SUDOEOF'
operator ALL=(root) NOPASSWD: \
    /usr/bin/systemctl start mywebapp, \
    /usr/bin/systemctl stop mywebapp, \
    /usr/bin/systemctl restart mywebapp, \
    /usr/bin/systemctl status mywebapp, \
    /usr/bin/systemctl reload nginx
SUDOEOF
chmod 440 /etc/sudoers.d/operator

echo "[4/9] Налаштування MariaDB..."
systemctl enable --now mariadb
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4;
DROP USER IF EXISTS '$DB_USER'@'localhost';
DROP USER IF EXISTS '$DB_USER'@'127.0.0.1';
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "[5/9] Розгортання застосунку..."
mkdir -p "$APP_DIR"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/app/app.py"           "$APP_DIR/app.py"
cp "$SCRIPT_DIR/app/migrate.py"       "$APP_DIR/migrate.py"
cp "$SCRIPT_DIR/app/requirements.txt" "$APP_DIR/requirements.txt"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install -q -r "$APP_DIR/requirements.txt"
chown -R mywebapp:mywebapp "$APP_DIR"

echo "[6/9] Встановлення systemd-сервісу..."
sed "s/__DB_PASSWORD__/$DB_PASSWORD/g" "$SCRIPT_DIR/deploy/mywebapp.service" > /etc/systemd/system/mywebapp.service
cp "$SCRIPT_DIR/deploy/mywebapp.socket" /etc/systemd/system/mywebapp.socket
systemctl daemon-reload
systemctl enable mywebapp.socket mywebapp.service
systemctl start mywebapp.socket
systemctl start mywebapp.service

echo "[7/9] Налаштування nginx..."
cp "$SCRIPT_DIR/deploy/nginx_mywebapp.conf" /etc/nginx/sites-available/mywebapp
ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "[8/9] Створення /home/student/gradebook..."
mkdir -p /home/student
echo "$N" > /home/student/gradebook
chown student:student /home/student/gradebook
chmod 644 /home/student/gradebook

echo "[9/9] Блокування дефолтного користувача..."
DEFAULT_USER="${SUDO_USER:-ubuntu}"
if [ "$DEFAULT_USER" != "root" ] && id "$DEFAULT_USER" &>/dev/null; then
    passwd -l "$DEFAULT_USER" || true
fi

echo "$DB_PASSWORD" > /root/.mywebapp_db_pass
chmod 600 /root/.mywebapp_db_pass

sleep 2
echo ""
echo "--- Health check ---"
curl --max-time 5 -sf http://127.0.0.1:8000/health/alive && echo " /health/alive  → OK" || echo " /health/alive  → FAIL"
curl --max-time 5 -sf http://127.0.0.1:8000/health/ready && echo " /health/ready  → OK" || echo " /health/ready  → FAIL"
curl --max-time 5 -sf http://127.0.0.1/items && echo " /items  → OK" || echo " /items  → FAIL"
echo "--- Done ---"
