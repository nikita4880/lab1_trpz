#!/usr/bin/env bash
# setup_runner.sh — налаштування self-hosted GitHub Actions runner (Ubuntu 24.04)
# Запуск: bash setup_runner.sh
# ВАЖЛИВО: токен реєстрації runner НЕ зберігається в репозиторії!
#          Крок реєстрації виконується вручну після запуску скрипта.

set -euo pipefail

RUNNER_VERSION="2.317.0"
RUNNER_USER="${RUNNER_USER:-runner}"

echo "==> [1/4] Встановлення залежностей"
sudo apt-get update -q
sudo apt-get install -y -q \
  curl git jq docker.io openssh-client

sudo systemctl enable --now docker
sudo usermod -aG docker "${RUNNER_USER:-$USER}"

echo "==> [2/4] Створення користувача для runner"
if ! id "$RUNNER_USER" &>/dev/null; then
  sudo useradd -m -s /bin/bash "$RUNNER_USER"
  sudo usermod -aG docker "$RUNNER_USER"
fi

echo "==> [3/4] Завантаження GitHub Actions Runner"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"

curl -fsSL \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
  -o /tmp/runner.tar.gz

sudo -u "$RUNNER_USER" tar -xzf /tmp/runner.tar.gz -C "$RUNNER_DIR"
rm /tmp/runner.tar.gz

echo ""
echo "==> [4/4] Реєстрація runner (виконується ВРУЧНУ)"
echo ""
echo "  1. Відкрий GitHub: Settings → Actions → Runners → New self-hosted runner"
echo "  2. Скопіюй токен реєстрації (Registration token)"
echo "  3. Виконай:"
echo ""
echo "     sudo -u ${RUNNER_USER} bash -c '"
echo "       cd /home/${RUNNER_USER}/actions-runner && \\"
echo "       ./config.sh \\"
echo "         --url https://github.com/nikita4880/lab1_trpz \\"
echo "         --token <ТВІЙ_ТОКЕН> \\"
echo "         --name lab3-runner \\"
echo "         --labels self-hosted,lab3 \\"
echo "         --unattended'"
echo ""
echo "  4. Встанови як systemd-сервіс:"
echo ""
echo "     cd /home/${RUNNER_USER}/actions-runner"
echo "     sudo ./svc.sh install ${RUNNER_USER}"
echo "     sudo ./svc.sh start"
echo "     sudo ./svc.sh status"
echo ""
echo "  5. Після завершення лабораторної — зупини runner:"
echo "     sudo ./svc.sh stop"
echo "     sudo ./svc.sh uninstall"
