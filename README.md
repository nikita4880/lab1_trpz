# Лабораторна робота №1 — mywebapp (Simple Inventory)

## Варіант індивідуального завдання

**N = 8**

| Параметр | Формула | Результат | Значення |
|---|---|---|---|
| V2 | (8 % 2) + 1 | **1** | Конфігурація: аргументи командного рядка; БД: MariaDB |
| V3 | (8 % 3) + 1 | **3** | Застосунок: Simple Inventory |
| V5 | (8 % 5) + 1 | **4** | Порт застосунку: **8000** |

---

## Опис застосунку

**Simple Inventory** — веб-сервіс обліку обладнання/предметів.

Об'єкт інвентарю:
- `id` — унікальний ідентифікатор
- `name` — назва предмету
- `quantity` — кількість
- `created_at` — дата створення запису

---

## Архітектура

```
client → nginx (порт 80) → mywebapp/systemd socket (127.0.0.1:8000) → MariaDB (127.0.0.1:3306)
```

---

## API ендпоінти

### Health

| Метод | Шлях | Опис |
|---|---|---|
| GET | `/health/alive` | Завжди повертає `200 OK` |
| GET | `/health/ready` | `200 OK` якщо БД доступна, `500` якщо ні |

> **Увага:** ендпоінти `/health/*` закриті nginx і доступні лише з самої ВМ.

### Кореневий ендпоінт

| Метод | Шлях | Опис |
|---|---|---|
| GET | `/` | HTML-сторінка зі списком усіх ендпоінтів |

### Бізнес-логіка

| Метод | Шлях | Body (JSON/form) | Опис |
|---|---|---|---|
| GET | `/items` | — | Список усіх предметів (id, name) |
| POST | `/items` | `name`, `quantity` | Створити новий запис |
| GET | `/items/<id>` | — | Деталі запису (id, name, quantity, created_at) |

Відповідь залежить від заголовку `Accept`:
- `Accept: text/html` → HTML-таблиця
- `Accept: application/json` → JSON

**Приклади:**

```bash
# Список предметів (JSON)
curl -H "Accept: application/json" http://localhost/items

# Список предметів (HTML)
curl -H "Accept: text/html" http://localhost/items

# Створити предмет
curl -X POST http://localhost/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Laptop", "quantity": 5}'

# Деталі предмету
curl -H "Accept: application/json" http://localhost/items/1
```

---

## Середовище розробки / локальний запуск

### Вимоги
- Python 3.10+
- MariaDB або MySQL (локально або в Docker)

### Встановлення залежностей

```bash
cd app/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Запуск локально

```bash
# Спочатку запустити міграцію
python migrate.py \
  --db-host 127.0.0.1 \
  --db-name mywebapp \
  --db-user root \
  --db-password yourpassword

# Запустити застосунок
python app.py \
  --host 127.0.0.1 \
  --port 8000 \
  --db-host 127.0.0.1 \
  --db-name mywebapp \
  --db-user mywebapp \
  --db-password yourpassword
```

---

## Розгортання на віртуальній машині

### Базовий образ

- **Ubuntu Server 24.04 LTS**
- Офіційний образ: https://ubuntu.com/download/server
- Завантажувати: `ubuntu-24.04-live-server-amd64.iso`

### Вимоги до ресурсів

| Ресурс | Мінімум |
|---|---|
| CPU | 1 vCPU |
| RAM | 1 GB |
| Disk | 10 GB |
| Мережа | 1 мережевий інтерфейс (NAT або Bridged) |

### Налаштування при встановленні OS

Стандартне встановлення Ubuntu Server. Спеціальних налаштувань розбивки диску не потрібно. При встановленні створити користувача `ubuntu` (він буде заблокований після розгортання).

### Вхід на ВМ

```bash
# При початковому встановленні
ssh ubuntu@<IP-адреса-ВМ>
# або через консоль гіпервізора
```

Credentials за замовчуванням: `ubuntu` / пароль що задали при встановленні OS.

### Запуск автоматизації

```bash
git clone https://github.com/nikita4880/TRPZ.git
cd TRPZ/lab1

# Запустити інсталятор від root
sudo bash install.sh
```

Після виконання скрипта:
- Застосунок запущений та доступний на порту 80
- Пароль до БД збережено у `/root/.mywebapp_db_pass`
- Файл `/home/student/gradebook` містить число `8`

---

## Користувачі в системі

| Користувач | Призначення | Пароль за замовчуванням |
|---|---|---|
| `student` | Робочий користувач | задається при інсталяції |
| `teacher` | Перевірка роботи | `12345678` (потрібна зміна при першому вході) |
| `mywebapp` | Системний, запуск застосунку | — (nologin) |
| `operator` | Керування сервісами | `12345678` (потрібна зміна при першому вході) |

### Команди для operator

```bash
sudo systemctl start mywebapp
sudo systemctl stop mywebapp
sudo systemctl restart mywebapp
sudo systemctl status mywebapp
sudo systemctl reload nginx
```

---

## Тестування розгорнутої системи

```bash
# 1. Перевірка стану сервісів
systemctl status mywebapp
systemctl status nginx
systemctl status mariadb

# 2. Health endpoints (з самої ВМ)
curl http://127.0.0.1:8000/health/alive
curl http://127.0.0.1:8000/health/ready

# 3. API через nginx (ззовні або з ВМ)
curl -H "Accept: application/json" http://localhost/items

# 4. Створити тестовий запис
curl -X POST http://localhost/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Monitor", "quantity": 3}'

# 5. Перевірити запис
curl -H "Accept: application/json" http://localhost/items/1

# 6. HTML версія
curl -H "Accept: text/html" http://localhost/items

# 7. Перевірка що /health недоступний ззовні (має повернути 403)
curl -v http://localhost/health/alive

# 8. Перевірка socket activation
systemctl stop mywebapp
curl http://localhost/items   # systemd має автоматично запустити сервіс
systemctl status mywebapp     # має бути active
```

---

## Структура репозиторію

```
.
├── README.md
├── install.sh              # Єдина точка входу автоматизації
├── app/
│   ├── app.py              # Веб-застосунок (Flask)
│   ├── migrate.py          # Скрипт міграції БД
│   └── requirements.txt
└── deploy/
    ├── mywebapp.service    # systemd unit
    ├── mywebapp.socket     # systemd socket (socket activation)
    ├── nginx_mywebapp.conf # nginx конфіг
    └── sudoers_operator    # sudo правила для operator
```
