# Лабораторна робота №3 — CI/CD

**Варіант N=8** | Flask + MariaDB + Nginx  
**Репозиторій:** https://github.com/nikita4880/lab1_trpz

---

## Зміст

1. [Структура файлів](#структура-файлів)
2. [CI Pipeline](#ci-pipeline)
3. [CD Pipeline](#cd-pipeline)
4. [Налаштування target node](#налаштування-target-node)
5. [Налаштування self-hosted runner](#налаштування-self-hosted-runner)
6. [GitHub Secrets](#github-secrets)
7. [Демонстрація](#демонстрація)

---

## Структура файлів

```
lab1_trpz/
├── app/
│   ├── app.py
│   ├── migrate.py
│   ├── requirements.txt
│   └── tests.py                        # автоматичні тести (16 тестів, coverage ~70%)
├── deploy/
│   ├── setup_target.sh                 # налаштування target VM
│   ├── setup_runner.sh                 # налаштування runner VM
│   ├── deploy.sh                       # скрипт розгортання (запускається на target)
│   └── verify.sh                       # скрипт верифікації (8 перевірок)
├── .github/
│   └── workflows/
│       ├── ci.yml                      # CI: lint + test + build image
│       └── cd.yml                      # CD: deploy on annotated tag
├── .yamllint.yml
├── .hadolint.yaml
├── Dockerfile.debian.optimized         # production образ (використовується в CI/CD)
├── Dockerfile.debian                   # для порівняння (лаб №2)
├── Dockerfile.alpine                   # для порівняння (лаб №2)
└── docker-compose.yml                  # для локального запуску (лаб №2)
```

---

## CI Pipeline

**Файл:** `.github/workflows/ci.yml`

Запускається на:
- кожен `push` у `master`
- кожен `push` анотованого тегу `v*`
- кожен Pull Request у `master`

### Граф залежностей jobs

```
lint ──► test ──► build (тільки push, не PR)
```

### lint

Перевіряє якість коду:

| Інструмент | Що перевіряє |
|---|---|
| `flake8` | Python style, max-line-length=120 |
| `mypy` | Python type checking |
| `hadolint` | Dockerfile lint |
| `shellcheck` | Shell-скрипти в `deploy/` |
| `yamllint` | YAML файли |

### test

```yaml
pytest app/tests.py \
  --cov=app \
  --cov-report=term-missing \
  --cov-report=xml:coverage.xml \
  --cov-report=html:coverage_html \
  --cov-fail-under=40
```

Coverage report зберігається як артефакт `coverage-report` (42 KB).

### build

Збирає production-образ і публікує в GHCR:

| Подія | Теги образу |
|---|---|
| Push у гілку | `latest`, `sha-<full-commit-hash>` |
| Анотований тег `v*` | `stable`, `<tag>` (наприклад `v1.0.3`) |

Образ: `ghcr.io/nikita4880/lab1_trpz`

---

## CD Pipeline

**Файл:** `.github/workflows/cd.yml`

Запускається тільки на анотовані теги `v*`.  
Виконується на **self-hosted runner** (`lab1`, Linux/X64).

### Кроки

```
1. SSH → передача deploy.sh на target node → запуск
2. SSH → передача verify.sh на target node → запуск
3. Cleanup SSH key
```

### deploy.sh — що робить

1. `docker pull <IMAGE>` — завантаження нового образу
2. Запуск міграції БД (`migrate.py`) у тимчасовому контейнері
3. `docker stop/rm mywebapp` — зупинка старого контейнера
4. `docker run -d --name mywebapp ...` — запуск нового контейнера

### verify.sh — 8 перевірок

| # | Перевірка | Очікуваний результат |
|---|---|---|
| 1 | systemd-сервіс mywebapp | active |
| 2 | Docker-контейнер mywebapp | running |
| 3 | GET /health/alive (порт 8000) | HTTP 200 |
| 4 | GET /health/ready (порт 8000) | HTTP 200 |
| 5 | Nginx reverse proxy GET / | HTTP 200 |
| 6 | Nginx закриває /health/ зовні | HTTP 403 |
| 7 | GET /items | валідний JSON |
| 8 | POST /items | HTTP 201 |

### Запуск деплою (анотований тег)

```bash
git tag -a v1.0.3 -m "Release v1.0.3"
git push origin v1.0.3
```

---

## Налаштування target node

Target node — VM `lab1` (Ubuntu 24.04), IP: `192.168.1.33`.  
На ній запускається застосунок у Docker-контейнері.

### Що налаштовано

- **MariaDB** — слухає на `0.0.0.0:3306`, БД `mywebapp`, користувач `mywebapp`
- **Nginx** — reverse proxy на `127.0.0.1:8000`, `/health/` закритий (403)
- **Docker** — запускає контейнер `mywebapp`
- **systemd-юніт** — `/etc/systemd/system/mywebapp.service` керує контейнером

### Автоматизований скрипт налаштування

```bash
scp deploy/setup_target.sh teacher@<TARGET_IP>:/tmp/
ssh teacher@<TARGET_IP>
sudo DB_NAME=mywebapp DB_USER=mywebapp DB_PASSWORD=<пароль> bash /tmp/setup_target.sh
```

### Конфігурація контейнера

Зберігається в `/etc/mywebapp.env` (не в репозиторії — секретна інформація):

```
IMAGE=ghcr.io/nikita4880/lab1_trpz:stable
DB_HOST=172.17.0.1
DB_PORT=3306
DB_NAME=mywebapp
DB_USER=mywebapp
DB_PASSWORD=***
APP_PORT=8000
```

### Команди керування

```bash
sudo systemctl start mywebapp    # запустити
sudo systemctl stop mywebapp     # зупинити
sudo systemctl restart mywebapp  # перезапустити
sudo systemctl status mywebapp   # статус
journalctl -u mywebapp -f        # логи
```

---

## Налаштування self-hosted runner

Runner — окрема VM `lab3` (Ubuntu 24.04), IP: `192.168.1.35`.  
**Токен реєстрації НЕ додається в репозиторій.**

### Автоматизований скрипт

```bash
bash deploy/setup_runner.sh
```

Скрипт встановить Docker і завантажить runner. Реєстрація — вручну.

### Ручна реєстрація

1. GitHub → **Settings → Actions → Runners → New self-hosted runner**
2. Скопіювати токен реєстрації
3. Виконати на runner VM:

```bash
cd ~/actions-runner
./config.sh \
  --url https://github.com/nikita4880/lab1_trpz \
  --token <ТОКЕН> \
  --name lab1 \
  --unattended

sudo ./svc.sh install teacher
sudo ./svc.sh start
```

### SSH-доступ з runner на target

```bash
# На runner VM:
ssh-keygen -t ed25519 -f ~/.ssh/deploy_key -N ""
ssh-copy-id -i ~/.ssh/deploy_key.pub teacher@192.168.1.33

# Приватний ключ → GitHub Secret SSH_PRIVATE_KEY
cat ~/.ssh/deploy_key
```

### Після завершення лабораторної

```bash
cd ~/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove --token <ТОКЕН>
```

---

## GitHub Secrets

**Settings → Secrets and variables → Actions → Repository secrets:**

| Secret | Значення |
|---|---|
| `TARGET_HOST` | `192.168.1.33` |
| `TARGET_USER` | `teacher` |
| `SSH_PRIVATE_KEY` | Приватний SSH-ключ (ed25519) |
| `DB_NAME` | `mywebapp` |
| `DB_USER` | `mywebapp` |
| `DB_PASSWORD` | пароль БД |

---

## Демонстрація

### PR що пройшов всі перевірки

PR `lab3 → master` (#1) — всі checks зелені, merge дозволений:

```
✅ CI / Lint (pull_request)      16s
✅ CI / Test (pull_request)      14s
⭕ CI / Build & Push Image       skipped (PR, не push)
✅ No conflicts with base branch
```

Merge виконано — CI запустився на master і збудував образ в GHCR.

### PR що не може бути злитий

Для демонстрації створіть PR з навмисною помилкою:

```bash
git checkout -b bad-pr
echo "def broken" >> app/app.py   # синтаксична помилка
git add app/app.py
git commit -m "intentional error for demo"
git push origin bad-pr
```

Відкрийте PR `bad-pr → master` — lint впаде, merge буде заблокований (branch protection rules).

### Звіт покриття коду тестами

Артефакт `coverage-report` (42 KB) зберігається в кожному CI run.

Результати тестів:
```
app/tests.py::TestHealthEndpoints::test_health_alive          PASSED
app/tests.py::TestHealthEndpoints::test_health_ready_ok       PASSED
app/tests.py::TestHealthEndpoints::test_health_ready_db_error PASSED
app/tests.py::TestIndexEndpoint::test_index_returns_html      PASSED
app/tests.py::TestListItems::test_list_items_json_empty       PASSED
app/tests.py::TestListItems::test_list_items_json_with_data   PASSED
app/tests.py::TestListItems::test_list_items_html             PASSED
app/tests.py::TestCreateItem::test_create_item_success_json   PASSED
app/tests.py::TestCreateItem::test_create_item_missing_name   PASSED
app/tests.py::TestCreateItem::test_create_item_invalid_quantity PASSED
app/tests.py::TestCreateItem::test_create_item_missing_quantity PASSED
app/tests.py::TestCreateItem::test_create_item_html_response  PASSED
app/tests.py::TestGetItem::test_get_item_found_json           PASSED
app/tests.py::TestGetItem::test_get_item_not_found_json       PASSED
app/tests.py::TestGetItem::test_get_item_not_found_html       PASSED
app/tests.py::TestGetItem::test_get_item_found_html           PASSED

16 passed in 0.45s
Coverage: 70% (> 40% ✅)
```

### Лог успішного розгортання і верифікації (CD #4, тег v1.0.3)

```
==> Розгортання образу: ghcr.io/nikita4880/lab1_trpz:v1.0.3
==> [1/3] Завантаження образу
v1.0.3: Pulling from nikita4880/lab1_trpz
Status: Downloaded newer image for ghcr.io/nikita4880/lab1_trpz:v1.0.3
==> [2/3] Запуск міграції
[migrate] Creating table 'items'...
[migrate] Creating index idx_items_name...
[migrate] Done.
==> [3/3] Перезапуск контейнера
<container_id>
Розгортання завершено: ghcr.io/nikita4880/lab1_trpz:v1.0.3

══════════════════════════════════════════
  Верифікація розгортання mywebapp
══════════════════════════════════════════
[1] systemd-сервіс mywebapp
  ✅ ***.service is active
[2] Docker-контейнер
  ✅ Container '***' is running
[3] GET /health/alive (прямо, порт 8000)
  ✅ /health/alive → HTTP 200
[4] GET /health/ready (прямо, порт 8000)
  ✅ /health/ready → HTTP 200 (БД доступна)
[5] Nginx reverse proxy — GET / через порт 80
  ✅ Nginx → HTTP 200 (proxy працює)
[6] Nginx — /health/ закритий зовні (403)
  ✅ /health/alive через nginx → HTTP 403 (правильно закритий)
[7] GET /items → JSON
  ✅ /items → валідний JSON
[8] POST /items → 201 Created
  ✅ POST /items → HTTP 201 Created
══════════════════════════════════════════
  ✅ Верифікація ПРОЙШЛА (0 помилок)
══════════════════════════════════════════
```

### Лог неуспішної верифікації

Для демонстрації зупиняємо контейнер перед верифікацією:

```bash
# На target node:
docker stop mywebapp
bash /tmp/verify.sh
```

```
══════════════════════════════════════════
  Верифікація розгортання mywebapp
══════════════════════════════════════════
[1] systemd-сервіс mywebapp
  ❌ ***.service is NOT active
[2] Docker-контейнер
  ❌ Container '***' is NOT running
[3] GET /health/alive (прямо, порт 8000)
  ❌ /health/alive → HTTP 000 (очікувалось 200)
[4] GET /health/ready (прямо, порт 8000)
  ❌ /health/ready → HTTP 000 (БД недоступна або сервіс не готовий)
[5] Nginx reverse proxy — GET / через порт 80
  ❌ Nginx → HTTP 502 (очікувалось 200)
[6] Nginx — /health/ закритий зовні (403)
  ❌ /health/alive через nginx → HTTP 000 (очікувалось 403)
[7] GET /items → JSON
  ❌ /items → невалідна відповідь: ERROR
[8] POST /items → 201 Created
  ❌ POST /items → HTTP 000 (очікувалось 201)
══════════════════════════════════════════
  ❌ Верифікація ПРОВАЛЕНА (8 помилок)
══════════════════════════════════════════
```
