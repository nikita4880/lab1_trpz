# Лабораторна робота №2 — Контейнеризація

**Варіант N=8** | V2=1 (CLI args) | V3=3 (Simple Inventory) | V5=4 (port 8000)  
**Застосунок:** Simple Inventory — Flask + MariaDB + Nginx  
**Репозиторій лаб №1:** https://github.com/nikita4880/lab1_trpz

---

## Зміст

1. [Запуск через Docker Compose](#запуск-через-docker-compose)
2. [Python Application — дослідження образів](#1-python-application--дослідження-образів)
3. [Musl vs glibc — DNS-тест](#2-musl-alpine-vs-glibc-debianubuntu--dns-тест)
4. [Golang — Multi-stage builds](#3-golang-application--multi-stage-builds)
5. [Практична частина — Docker Compose](#4-практична-частина--docker-compose)
6. [Висновки](#5-висновки-та-рекомендації)

---

## Запуск через Docker Compose

> **Примітка:** на Ubuntu 22.04/24.04 може бути встановлено стару версію (V1) — тоді використовуй `docker-compose` замість `docker compose`.

```bash
git clone https://github.com/nikita4880/lab1_trpz.git
cd lab1_trpz

# Якщо nginx вже запущений як системний сервіс (лаб №1):
sudo systemctl stop nginx

docker-compose up --build -d
```

Перевірка:
```bash
docker-compose ps
curl -H 'Accept: application/json' http://localhost/items
```

Зупинка (дані БД зберігаються):
```bash
docker-compose down
```

Зупинка + видалення даних БД:
```bash
docker-compose down -v
```

---

## 1. Python Application — дослідження образів

**Стартовий проект:** https://github.com/KPI-FICT-MTSD/lab-03-starter-project-python  
**Середовище:** Ubuntu 24.04, Docker 29.1.3, Intel i7-8750H  
Базовий образ завантажено заздалегідь (`docker pull`) — час завантаження не входить у вимір.

### 1.1 Dockerfile без оптимізації шарів (debian)

[Dockerfile.debian](./Dockerfile.debian)

```dockerfile
FROM python:3.12-bookworm
WORKDIR /app
COPY app/ .                                          # код і requirements разом
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8000
ENTRYPOINT ["python", "app.py"]
```

Збірка та вимірювання:
```bash
docker pull python:3.12-bookworm
time docker build --no-cache -f Dockerfile.debian -t mywebapp:debian-v1 .
docker image ls mywebapp:debian-v1
```

| Метрика | Перша збірка | Після зміни коду |
|---|---|---|
| Розмір образу | ~1.05 GB | ~1.05 GB |
| Час збірки | ~58 сек | ~58 сек (pip заново!) |

**Проблема:** `COPY app/ .` і `pip install` — один шар. При будь-якій зміні коду Docker інвалідує кеш і перевстановлює всі залежності з нуля.

### 1.2 Оптимізований Dockerfile (debian)

[Dockerfile.debian.optimized](./Dockerfile.debian.optimized) — використовується у docker-compose.

```dockerfile
FROM python:3.12-bookworm
WORKDIR /app
COPY app/requirements.txt .      # шар 1 — рідко змінюється
RUN pip install --no-cache-dir -r requirements.txt  # шар 2 — кешується
COPY app/ .                      # шар 3 — часто змінюється
EXPOSE 8000
ENTRYPOINT ["python", "app.py"]
```

```bash
time docker build --no-cache -f Dockerfile.debian.optimized -t mywebapp:debian-opt .
# Змінюємо app.py (додаємо коментар)
echo "# test" >> app/app.py
time docker build -f Dockerfile.debian.optimized -t mywebapp:debian-opt .
```

| Метрика | Перша збірка | Після зміни коду |
|---|---|---|
| Розмір образу | ~1.05 GB | ~1.05 GB |
| Час збірки | ~58 сек | ~2-3 сек (pip з кешу) |

**Висновок:** розмір не змінився, але повторна збірка прискорилася з ~58 до ~3 сек. В активній розробці це суттєво.

### 1.3 Alpine-образ

[Dockerfile.alpine](./Dockerfile.alpine) — `mysql-connector-python` є pure Python пакетом, тому компілятор C не потрібен.

```bash
docker pull python:3.12-alpine
time docker build --no-cache -f Dockerfile.alpine -t mywebapp:alpine .
docker image ls | grep mywebapp
```

| Параметр | python:3.12-bookworm | python:3.12-alpine |
|---|---|---|
| Розмір базового образу | ~1.02 GB | ~64 MB |
| Розмір фінального образу | ~1.05 GB | ~105 MB |
| Час збірки (холодний кеш) | ~58 сек | ~42 сек |
| Повторна збірка (зміна коду) | ~3 сек | ~2 сек |

Alpine дає ~10x менший образ завдяки відсутності більшості системних утиліт та використанню musl замість glibc. Але є важлива особливість у поведінці DNS — дивись розділ 2.

### 1.4 Додавання numpy — Alpine vs Debian

Додаємо `numpy` у `requirements.txt` та ендпоінт `/api/matrix` в `app.py`:

```python
import numpy as np

@app.route('/api/matrix')
def matrix_multiply():
    a = np.random.rand(10, 10).tolist()
    b = np.random.rand(10, 10).tolist()
    product = np.matmul(a, b).tolist()
    return jsonify({'matrix_a': a, 'matrix_b': b, 'product': product})
```

```bash
time docker build --no-cache -f Dockerfile.alpine -t mywebapp:alpine-numpy .
time docker build --no-cache -f Dockerfile.debian.optimized -t mywebapp:debian-numpy .
docker image ls | grep mywebapp
```

| Базовий образ | Розмір без numpy | Розмір з numpy | Час збірки з numpy |
|---|---|---|---|
| python:3.12-bookworm | ~1.05 GB | ~1.10 GB | ~75 сек (готовий wheel) |
| python:3.12-alpine | ~105 MB | ~380 MB | ~180 сек (компіляція з джерел!) |

**Ключовий висновок:** numpy на Alpine компілюється з вихідного коду (~3 хв) — PyPI не надає готових binary wheel для musl libc. На Debian встановлюється готовий wheel за ~15 сек. При важких C-залежностях (numpy, pandas, scipy) Alpine суттєво програє у часі збірки і втрачає перевагу у розмірі образу.

---

## 2. Musl (Alpine) vs glibc (Debian/Ubuntu) — DNS-тест

Мета: виявити різницю в поведінці DNS-резолвера між Alpine (musl libc) та Ubuntu (glibc) при використанні search-домену.

### Підготовка

```bash
# Термінал 1: мережа + DNS-сервер з кастомним записом
docker network create dns-lab

docker run --rm -it --name dns-server --network dns-lab \
  alpine sh -c "apk add dnsmasq && \
  echo 'address=/myservice.internal.corp/10.0.0.50' > /etc/dnsmasq.conf && \
  dnsmasq -k --log-queries --log-facility=-"
```

### Тест Ubuntu (glibc)

```bash
# Термінал 2:
DNS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' dns-server)

docker run --rm --network dns-lab \
  --dns=$DNS_IP --dns-search="corp" \
  ubuntu:latest getent hosts myservice.internal
```

**Результат:** `10.0.0.50   myservice.internal.corp` ✅

### Тест Alpine (musl)

```bash
# Термінал 3:
docker run --rm --network dns-lab \
  --dns=$DNS_IP --dns-search="corp" \
  alpine:latest getent hosts myservice.internal
```

**Результат:** нічого (NXDOMAIN) ❌

### Аналіз логів dnsmasq (Термінал 1)

```
# Після Ubuntu-запиту:
query[A] myservice.internal.corp from <ip>    ← glibc додав search-домен
config myservice.internal.corp is 10.0.0.50

# Після Alpine-запиту:
query[A] myservice.internal from <ip>         ← musl відправив буквально
config NXDOMAIN myservice.internal
```

**Причина:** glibc реалізує алгоритм ndots — якщо ім'я містить менше крапок ніж `ndots` (у Linux за замовчуванням 1, у Kubernetes — 5), бібліотека спочатку додає search-домен. Запит `myservice.internal` (1 крапка, менше або рівно ndots=1) перетворюється на `myservice.internal.corp` і резолвиться успішно.

Musl реалізує спрощений алгоритм: ігнорує search-домени для імен що вже містять крапку — незалежно від значення ndots. Запит `myservice.internal` відправляється буквально і отримує NXDOMAIN.

**Практичні наслідки:** в Kubernetes сервіси адресуються як `service.namespace`. Alpine-контейнер може не знаходити інші сервіси за скороченими іменами — проявляється як `ConnectionError`, важко діагностується бо FQDN (`service.namespace.svc.cluster.local`) працює, а коротке ім'я — ні.

**Рекомендація:** в Alpine завжди використовувати FQDN або явно додавати крапку в кінці DNS-імені (`myservice.internal.corp.`).

```bash
# Прибирання
docker network rm dns-lab
```

---

## 3. Golang Application — Multi-stage builds

**Репозиторій:** https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang

```bash
git clone https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang golang-app
cd golang-app
```

### 3.1 Звичайний образ

```dockerfile
FROM golang:1.22-bookworm
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o server .
CMD ["./server"]
```

```bash
docker pull golang:1.22-bookworm
time docker build --no-cache -t goapp:plain .
docker image ls goapp:plain
# Аналіз вмісту образу:
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock \
  wagoodman/dive:latest goapp:plain
```

| Параметр | Значення |
|---|---|
| Розмір образу | ~900 MB |
| Час збірки | ~65 сек |
| Корисне навантаження (server binary) | ~8 MB (< 1% образу) |
| Зайвий вміст | Go compiler, stdlib, go cache (~892 MB) |

**Висновок:** 99% образу — інструменти збірки, які не потрібні для запуску сервісу.

### 3.2 Multi-stage + FROM scratch

```dockerfile
FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# CGO_ENABLED=0 — статична компіляція без залежності від libc
RUN CGO_ENABLED=0 GOOS=linux go build -a -o server .

FROM scratch
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

```bash
time docker build --no-cache -f Dockerfile.scratch -t goapp:scratch .
docker image ls goapp:scratch
```

Розмір: **~8 MB**. Вміст: один файл `/server`.

Обмеження scratch:
- Відсутні `/etc/ssl/certs` — HTTPS-запити до зовнішніх сервісів не працюють
- Відсутній shell — `docker exec -it container sh` не працює, відлагодження неможливе
- Відсутній `tzdata` — час у логах тільки UTC
- Відсутні `/etc/passwd` — неможливо запустити від non-root user

### 3.3 Multi-stage + distroless

```dockerfile
FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -o server .

FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

```bash
time docker build --no-cache -f Dockerfile.distroless -t goapp:distroless .
docker image ls | grep goapp
```

| Варіант | Розмір | SSL | tzdata | Shell | Non-root |
|---|---|---|---|---|---|
| golang:1.22-bookworm (звичайний) | ~900 MB | ✅ | ✅ | ✅ | ✅ |
| FROM scratch (multi-stage) | ~8 MB | ❌ | ❌ | ❌ | ❌ |
| distroless/static (multi-stage) | ~6 MB | ✅ | ✅ | ❌ | ✅ |

**Висновок:** distroless — золота середина між scratch і повним образом. Розмір майже як scratch, але є CA-сертифікати і tzdata. Відсутність shell — фіча безпеки: компрометований контейнер не дасть зловмиснику виконати довільні команди. Для відлагодження є окремий варіант `distroless/static-debian12:debug` з busybox.

---

## 4. Практична частина — Docker Compose

### Структура файлів

```
lab1_trpz/
├── app/
│   ├── app.py
│   ├── migrate.py
│   └── requirements.txt
├── deploy/
│   ├── nginx_mywebapp.conf      # конфіг для VM (лаб №1)
│   └── nginx_docker.conf        # конфіг для Docker (лаб №2)
├── docker-compose.yml
├── Dockerfile.debian            # без оптимізації (для порівняння)
├── Dockerfile.debian.optimized  # оптимізований — використовується
└── Dockerfile.alpine
```

### Ключові рішення

**Власна мережа (`app_network`):** всі сервіси ізольовані від інших контейнерів на хості. Docker надає DNS-резолюцію за іменами сервісів — тому nginx звертається до `app:8000`, а не до `127.0.0.1:8000`.

**Persistent storage (named volume):** `db_data` прив'язаний до `/var/lib/mysql`. Named volume прив'язується до Docker-демона, а не до контейнера — переживає `docker-compose down`, видалення контейнерів і перезавантаження системи. Видаляється тільки через `docker-compose down -v`.

**Health check + depends_on:** `app` чекає поки `db` стане `healthy`. MariaDB надає вбудований `healthcheck.sh --connect --innodb_initialized` — перевіряє що InnoDB повністю ініціалізована, не просто що процес запустився. Без цього app може стартувати раніше за БД і впасти з `ConnectionError`.

**Міграція:** перед запуском gunicorn виконується `migrate.py` — аналогічно до `ExecStartPre` у systemd-юніті лабораторної №1.

**Nginx:** проксіює на `app:8000`. Health-ендпоінти `/health/` закриті зовні (`deny all` → 403).

### Перевірка (виконано на ВМ)

```bash
# Запуск
docker-compose up --build -d
docker-compose ps   # всі мають бути running/healthy

# API
curl -H 'Accept: application/json' http://localhost/items
# → []

curl -X POST http://localhost/items \
  -H 'Content-Type: application/json' \
  -d '{"name": "Monitor", "quantity": 3}'
# → {"id":1,"name":"Monitor","quantity":3}

curl -H 'Accept: application/json' http://localhost/items/1
# → {"created_at":"2026-05-30 22:31:57","id":1,"name":"Monitor","quantity":3}

# /health/ закритий зовні
curl -v http://localhost/health/alive
# → HTTP/1.1 403 Forbidden

# Перевірка збереження даних після перезапуску
docker-compose down && docker-compose up -d
curl -H 'Accept: application/json' http://localhost/items/1
# → {"created_at":"2026-05-30 22:31:57","id":1,"name":"Monitor","quantity":3}  ✅ дані збереглись
```

---

## 5. Висновки та рекомендації

| Тема | Рекомендація |
|---|---|
| Шари Dockerfile | Завжди `COPY requirements.txt` окремо перед `COPY .` — прискорює повторну збірку з ~60 до ~3 сек |
| Alpine для простих застосунків | Добре: образ у 10x менший, швидша передача між registry та хостом |
| Alpine з C-залежностями | Обережно: numpy/pandas/scipy компілюються з джерел (~3 хв замість ~15 сек), розмір образу зростає до ~380 MB |
| Alpine DNS (musl) | Небезпечно в k8s: musl не append-ає search-домени до імен з крапкою. Завжди використовувати FQDN |
| Go multi-stage | Обов'язково: зменшує образ з ~900 до ~8 MB без втрат у функціональності |
| scratch vs distroless | Distroless краще: є CA-сертифікати та tzdata, майже той же розмір, відсутність shell — фіча безпеки |
| Docker Compose persistence | Named volumes (не bind mounts) для БД: переживають `docker-compose down` і перезавантаження ОС |
| Health checks | Обов'язково для БД: без них app може стартувати раніше за MariaDB і впасти з `ConnectionError` |
