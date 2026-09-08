#!/usr/bin/env bash
# Один генератор docker-compose.yml на все схемы установки.
#
# В апстриме шесть почти одинаковых файлов (nginx/caddy × panel/node/panel+node)
# несут каждый свою копию compose. Правка в одном не доезжает до остальных — так
# и разъехались теги страницы подписки. Здесь сервис описан один раз, а роль и
# прокси только выбирают, какие из них попадут в файл.

# Шаблоны используют {{КЛЮЧ}} вместо подстановки прямо в heredoc: иначе каждый
# $ в YAML пришлось бы экранировать, а забытый \ тихо ломает compose.
declare -gA T32_TPL=()

t32::compose::__subst() {
    local text; text="$(cat)"
    local key
    for key in "${!T32_TPL[@]}"; do
        text="${text//\{\{$key\}\}/${T32_TPL[$key]}}"
    done
    # Незакрытый плейсхолдер — это опечатка в шаблоне, а не «ну и ладно».
    if [[ $text =~ \{\{([A-Z_]+)\}\} ]]; then
        t32::die 70 "В шаблоне compose осталась неподставленная переменная {{${BASH_REMATCH[1]}}}"
    fi
    printf '%s\n' "$text"
}

t32::compose::__header() {
    cat <<'YAML'
x-common: &common
  ulimits:
    nofile:
      soft: 1048576
      hard: 1048576
  restart: always

x-logging: &logging
  logging:
    driver: json-file
    options:
      max-size: 100m
      max-file: 5

x-networks: &networks
  networks:
    - remnawave-network

x-env: &env
  env_file: .env

services:
YAML
}

t32::compose::__svc_db() {
    cat <<'YAML'
  remnawave-db:
    image: {{IMAGE_DB}}
    container_name: remnawave-db
    hostname: remnawave-db
    shm_size: 512mb
    <<: [*common, *logging, *env, *networks]
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
      - TZ=UTC
    ports:
      - '127.0.0.1:6767:5432'
    volumes:
      - remnawave-db-data:/var/lib/postgresql
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3

YAML
}

t32::compose::__svc_redis() {
    cat <<'YAML'
  remnawave-redis:
    image: {{IMAGE_REDIS}}
    container_name: remnawave-redis
    hostname: remnawave-redis
    <<: [*common, *logging, *networks]
    volumes:
      - valkey-socket:/var/run/valkey
    command: >
      valkey-server
      --save ""
      --appendonly no
      --maxmemory-policy noeviction
      --loglevel warning
      --unixsocket /var/run/valkey/valkey.sock
      --unixsocketperm 777
      --port 0
    healthcheck:
      test: ['CMD', 'valkey-cli', '-s', '/var/run/valkey/valkey.sock', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3

YAML
}

t32::compose::__svc_backend() {
    cat <<'YAML'
  remnawave:
    image: {{IMAGE_BACKEND}}
    container_name: remnawave
    hostname: remnawave
    <<: [*common, *logging, *env, *networks]
    volumes:
      - valkey-socket:/var/run/valkey
    ports:
      - '127.0.0.1:3000:${APP_PORT:-3000}'
      - '127.0.0.1:3001:${METRICS_PORT:-3001}'
    healthcheck:
      test: ['CMD-SHELL', 'curl -f http://localhost:${METRICS_PORT:-3001}/health']
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy

YAML
}

t32::compose::__svc_subpage() {
    cat <<'YAML'
  remnawave-subscription-page:
    image: {{IMAGE_SUBPAGE}}
    container_name: remnawave-subscription-page
    hostname: remnawave-subscription-page
    <<: [*common, *logging, *networks]
    depends_on:
      remnawave:
        condition: service_healthy
    environment:
      - REMNAWAVE_PANEL_URL=http://remnawave:3000
      - APP_PORT=3010
      - REMNAWAVE_API_TOKEN=${REMNAWAVE_API_TOKEN}
    ports:
      - '127.0.0.1:3010:3010'

YAML
}

t32::compose::__svc_node() {
    cat <<'YAML'
  remnanode:
    image: {{IMAGE_NODE}}
    container_name: remnanode
    hostname: remnanode
    <<: [*common, *logging]
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      - NODE_PORT=${NODE_PORT:-2222}
      - SECRET_KEY=${NODE_SECRET_KEY}
    volumes:
      - /dev/shm:/dev/shm:rw

YAML
}

t32::compose::__svc_nginx() {
    cat <<'YAML'
  remnawave-nginx:
    image: {{IMAGE_NGINX}}
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    <<: [*common, *logging]
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - /dev/shm:/dev/shm:rw
      - /var/www/html:/var/www/html:ro
    command: sh -c 'rm -f /dev/shm/nginx.sock && exec nginx -g "daemon off;"'

YAML
}

t32::compose::__svc_caddy() {
    cat <<'YAML'
  remnawave-caddy:
    image: {{IMAGE_CADDY}}
    container_name: remnawave-caddy
    hostname: remnawave-caddy
    <<: [*common, *logging]
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
      - /var/www/html:/var/www/html:ro

YAML
}

t32::compose::__footer() {
    local role="$1" proxy="$2"
    cat <<'YAML'
networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: false

volumes:
YAML
    if [[ $role != node ]]; then
        cat <<'YAML'
  remnawave-db-data:
    name: remnawave-db-data
    driver: local
    external: false
  valkey-socket:
    name: valkey-socket
    driver: local
    external: false
YAML
    fi
    if [[ $proxy == caddy ]]; then
        cat <<'YAML'
  caddy-data:
    name: caddy-data
    driver: local
    external: false
  caddy-config:
    name: caddy-config
    driver: local
    external: false
YAML
    fi
    # У ноды без панели свои тома не нужны, но пустой ключ volumes: ломает
    # compose — кладём заглушку.
    if [[ $role == node && $proxy != caddy ]]; then
        printf '  remnanode-placeholder:\n    name: remnanode-placeholder\n'
    fi
}

# t32::compose::render <panel|node|panel-node> <nginx|caddy> — печатает compose.
t32::compose::render() {
    local role="$1" proxy="$2"

    case "$role" in panel|node|panel-node) ;; *) t32::die 64 "Неизвестная роль: '$role'" ;; esac
    case "$proxy" in nginx|caddy) ;; *) t32::die 64 "Неизвестный прокси: '$proxy'" ;; esac

    T32_TPL=(
        [IMAGE_DB]="$(t32::versions::image db)"
        [IMAGE_REDIS]="$(t32::versions::image redis)"
        [IMAGE_BACKEND]="$(t32::versions::image backend)"
        [IMAGE_SUBPAGE]="$(t32::versions::image subscription-page)"
        [IMAGE_NODE]="$(t32::versions::image node)"
        [IMAGE_NGINX]="$(t32::versions::image nginx)"
        [IMAGE_CADDY]="$(t32::versions::image caddy)"
    )

    {
        t32::compose::__header
        if [[ $role != node ]]; then
            t32::compose::__svc_db
            t32::compose::__svc_redis
            t32::compose::__svc_backend
            t32::compose::__svc_subpage
        fi
        if [[ $role != panel ]]; then
            t32::compose::__svc_node
        fi
        case "$proxy" in
            nginx) t32::compose::__svc_nginx ;;
            caddy) t32::compose::__svc_caddy ;;
        esac
        t32::compose::__footer "$role" "$proxy"
    } | t32::compose::__subst
}
