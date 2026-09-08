#!/usr/bin/env bash
# Генерация .env для панели и для ноды.
#
# Три вещи сделаны иначе, чем в апстриме:
#
# 1. Пароль Postgres генерируется, а не остаётся `postgres`. Порт базы висит на
#    127.0.0.1:6767, так что снаружи её не видно, но пароль по умолчанию — это
#    ещё и любой контейнер на том же хосте, и любой, кто пролез на сервер.
# 2. WEBHOOK_SECRET_HEADER генерируется. В апстриме там прибита одна и та же
#    строка на все установки, и лежит она в публичном репозитории: включив
#    вебхуки, владелец получает подпись, известную кому угодно.
# 3. Файл создаётся с правами 600 до того, как в него попадёт первый секрет.

# t32::env::__create <путь> — пустой файл с правами 600.
t32::env::__create() {
    local path="$1"
    : >"$path"
    chmod 600 "$path"
    t32::journal::record file "$path"
}

# t32::env::panel <каталог> <домен панели> <домен подписки>
# Печатает в stdout логин и пароль суперадмина — их надо показать владельцу.
t32::env::panel() {
    local dir="$1" panel_domain="$2" sub_domain="$3"
    local path="$dir/.env"

    local pg_pass app_secret webhook_secret metrics_user metrics_pass
    pg_pass="$(t32::secrets::password 32)"
    app_secret="$(t32::secrets::hex 64)"
    webhook_secret="$(t32::secrets::__draw 64 'A-Za-z0-9')"
    metrics_user="$(t32::secrets::username 12)"
    metrics_pass="$(t32::secrets::password 24)"

    t32::env::__create "$path"
    cat >"$path" <<ENV
### APP ###
APP_PORT=3000
METRICS_PORT=3001

### API ###
# max — по числу ядер, число — столько инстансов, -1 — ядра минус один.
# Больше физических ядер ставить нельзя.
API_INSTANCES=1

### DATABASE ###
DATABASE_URL="postgresql://postgres:${pg_pass}@remnawave-db:5432/postgres"

### REDIS ###
REDIS_SOCKET=/var/run/valkey/valkey.sock

### SECRETS ###
# Единственный ключ подписи панели: сессии админов, API-токены и перец к
# паролям. Заменишь — все админы разом потеряют доступ.
APP_SECRET=${app_secret}

# Сколько часов живёт сессия админа: 12–168.
JWT_AUTH_LIFETIME=168

### TELEGRAM ###
IS_TELEGRAM_NOTIFICATIONS_ENABLED=false
TELEGRAM_BOT_TOKEN=change_me
TELEGRAM_NOTIFY_USERS=change_me
TELEGRAM_NOTIFY_NODES=change_me
TELEGRAM_NOTIFY_CRM=change_me
TELEGRAM_NOTIFY_SERVICE=change_me
TELEGRAM_NOTIFY_TBLOCKER=change_me

### DOMAINS ###
PANEL_DOMAIN=${panel_domain}
FRONT_END_DOMAIN=${panel_domain}
# Без http/https и без слеша на конце.
SUB_PUBLIC_DOMAIN=${sub_domain}

### PROMETHEUS ###
# Метрики на http://127.0.0.1:\${METRICS_PORT}/metrics
METRICS_USER=${metrics_user}
METRICS_PASS=${metrics_pass}

### WEBHOOKS ###
WEBHOOK_ENABLED=false
WEBHOOK_URL=https://example.com/endpoint
# Ключ подписи payload: ровно 64 символа, только a-z A-Z 0-9.
# Сгенерирован для этой установки — не подставляй чужой.
WEBHOOK_SECRET_HEADER=${webhook_secret}

### NOTIFICATIONS ###
BANDWIDTH_USAGE_NOTIFICATIONS_ENABLED=false
BANDWIDTH_USAGE_NOTIFICATIONS_THRESHOLD=[60, 80]
NOT_CONNECTED_USERS_NOTIFICATIONS_ENABLED=false
NOT_CONNECTED_USERS_NOTIFICATIONS_AFTER_HOURS=[6, 24, 48]

### POSTGRES (для контейнера базы, приложением не читается) ###
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${pg_pass}
POSTGRES_DB=postgres

### SUBSCRIPTION PAGE ###
# Заполняется после того, как панель выдаст токен.
REMNAWAVE_API_TOKEN=
ENV
}

# t32::env::node <каталог> <ключ ноды> [порт]
t32::env::node() {
    local dir="$1" secret_key="$2" port="${3:-2222}"
    local path="$dir/.env"

    t32::env::__create "$path"
    cat >"$path" <<ENV
### NODE ###
NODE_PORT=${port}
# Ключ из панели: Ноды → нужная нода → SECRET_KEY.
NODE_SECRET_KEY=${secret_key}
ENV
}

# t32::env::set <файл> <ключ> <значение> — заменить или дописать строку.
t32::env::set() {
    local path="$1" key="$2" value="$3"
    [[ -f $path ]] || t32::die 66 "Нет файла окружения: $path"
    if grep -qE "^${key}=" "$path"; then
        # Значение подставляется через awk, а не sed: в токенах панели
        # встречаются / и &, на которых sed молча испортит строку.
        local tmp; tmp="$(mktemp)"
        awk -v k="$key" -v v="$value" \
            'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$path" >"$tmp"
        cat "$tmp" >"$path"
        rm -f "$tmp"
    else
        printf '%s=%s\n' "$key" "$value" >>"$path"
    fi
}

# t32::env::get <файл> <ключ>
t32::env::get() {
    local path="$1" key="$2"
    [[ -f $path ]] || t32::die 66 "Нет файла окружения: $path"
    # Без пайпа в head: тот закрывает поток на первой строке, sed получает
    # SIGPIPE, и под pipefail функция вернула бы ошибку на ровном месте.
    awk -v k="$key" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$path"
}
