#!/usr/bin/env bash
# Предполётные проверки: всё, что можно узнать до первой записи на диск.
#
# Апстрим проверяет только root и (с сентября 2026) свободное место перед
# апгрейдом на 3.x. Остальное всплывает уже на середине установки: занятый :443,
# домен, указывающий не на этот сервер, 1 ГБ памяти под панель, разъехавшиеся
# часы. Здесь всё это ловится заранее и одним списком, а не по одной ошибке за
# запуск.

T32_PREFLIGHT_FAILED=()
T32_PREFLIGHT_WARNED=()

t32::preflight::__fail() { T32_PREFLIGHT_FAILED+=("$1"); }
t32::preflight::__warn() { T32_PREFLIGHT_WARNED+=("$1"); }

t32::preflight::root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] && return 0
    t32::preflight::__fail "Запускать нужно от root: sudo bash install.sh"
}

t32::preflight::os() {
    local id ver
    if [[ ! -r /etc/os-release ]]; then
        t32::preflight::__fail "Не вижу /etc/os-release — система не опознана. Нужен Debian или Ubuntu."
        return 0
    fi
    # shellcheck source=/dev/null
    id="$(. /etc/os-release && printf '%s' "${ID:-}")"
    ver="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
    case "$id" in
        debian)
            [[ ${ver%%.*} -ge 12 ]] || t32::preflight::__fail "Debian $ver слишком старый, нужен 12 или новее."
            ;;
        ubuntu)
            [[ ${ver%%.*} -ge 22 ]] || t32::preflight::__fail "Ubuntu $ver слишком старый, нужен 22.04 или новее."
            ;;
        *)
            t32::preflight::__fail "Система '$id' не поддерживается. Нужен Debian 12+ или Ubuntu 22.04+."
            ;;
    esac
}

t32::preflight::arch() {
    local a; a="$(uname -m)"
    case "$a" in
        x86_64|amd64|aarch64|arm64) return 0 ;;
        *) t32::preflight::__fail "Архитектура $a не поддерживается: у образов Remnawave нет сборок под неё." ;;
    esac
}

# t32::preflight::memory <мегабайт>
t32::preflight::memory() {
    local need="$1" have
    have="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
    [[ $have -eq 0 ]] && return 0
    if [[ $have -lt $need ]]; then
        t32::preflight::__fail "Памяти ${have} МБ, нужно минимум ${need} МБ. Панель без swap уронит Postgres на миграциях."
    elif [[ $have -lt $((need * 2)) ]]; then
        t32::preflight::__warn "Памяти ${have} МБ — рабочий минимум, но под нагрузкой будет тесно (рекомендуется $((need * 2)) МБ)."
    fi
}

# t32::preflight::disk <гигабайт> [путь]
t32::preflight::disk() {
    local need="$1" path="${2:-/}" have
    have="$(df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -dc '0-9')"
    [[ -z ${have:-} ]] && return 0
    if [[ $have -lt $need ]]; then
        t32::preflight::__fail "На $path свободно ${have} ГБ, нужно ${need} ГБ: образы, база и логи не поместятся."
    fi
}

# t32::preflight::port <порт> — свободен ли, и кем занят.
t32::preflight::port() {
    local port="$1" holder
    command -v ss >/dev/null 2>&1 || return 0
    holder="$(ss -lntpH "sport = :$port" 2>/dev/null | head -1 || true)"
    [[ -z $holder ]] && return 0
    local proc; proc="$(sed -nE 's/.*users:\(\("([^"]+)".*/\1/p' <<<"$holder")"
    t32::preflight::__fail "Порт :$port занят процессом ${proc:-неизвестно}. Освободи его или останови сервис."
}

# t32::preflight::domain <домен> — резолвится ли он на этот сервер.
t32::preflight::domain() {
    local domain="$1" resolved my_ip
    command -v dig >/dev/null 2>&1 || { t32::preflight::__warn "Нет dig — проверку домена $domain пропускаю."; return 0; }
    resolved="$(dig +short A "$domain" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1 || true)"
    if [[ -z $resolved ]]; then
        t32::preflight::__fail "Домен $domain не резолвится в A-запись. Создай её и подожди обновления DNS."
        return 0
    fi
    my_ip="$(curl -fsS -m 10 https://api.ipify.org 2>/dev/null || true)"
    [[ -z $my_ip ]] && return 0
    if [[ $resolved != "$my_ip" ]]; then
        t32::preflight::__warn "Домен $domain смотрит на $resolved, а сервер — $my_ip. Это нормально за CDN, но Let's Encrypt по HTTP-01 не выпустится."
    fi
}

t32::preflight::clock() {
    # Reality и TLS ломаются при расхождении часов больше пары минут.
    if command -v timedatectl >/dev/null 2>&1; then
        local synced; synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo yes)"
        [[ $synced == yes ]] && return 0
        t32::preflight::__warn "Часы не синхронизированы по NTP. Reality и TLS-сертификаты этого не прощают: systemctl enable --now systemd-timesyncd"
    fi
}

t32::preflight::existing_install() {
    local dir
    for dir in /opt/remnawave /opt/remnanode; do
        [[ -d $dir ]] || continue
        t32::preflight::__warn "Каталог $dir уже есть — установка пойдёт поверх. Сделай бэкап, если там боевые данные."
    done
}

# t32::preflight::run <panel|node|panel-node> [домены...]
t32::preflight::run() {
    local role="$1"; shift || true
    T32_PREFLIGHT_FAILED=()
    T32_PREFLIGHT_WARNED=()

    t32::step "Проверяю сервер перед установкой"

    t32::preflight::root
    t32::preflight::os
    t32::preflight::arch
    t32::preflight::clock
    t32::preflight::existing_install
    t32::preflight::port 80
    t32::preflight::port 443

    case "$role" in
        panel|panel-node) t32::preflight::memory 2048; t32::preflight::disk 20 ;;
        node)             t32::preflight::memory 1024; t32::preflight::disk 10 ;;
        *)                t32::die 64 "Неизвестная роль: '$role'" ;;
    esac

    local d
    for d in "$@"; do t32::preflight::domain "$d"; done

    local w
    for w in "${T32_PREFLIGHT_WARNED[@]+"${T32_PREFLIGHT_WARNED[@]}"}"; do t32::warn "$w"; done

    if [[ ${#T32_PREFLIGHT_FAILED[@]} -gt 0 ]]; then
        printf '\n' >&2
        t32::err "Установка не начнётся, пока не исправлено:"
        local f
        for f in "${T32_PREFLIGHT_FAILED[@]}"; do printf '        — %s\n' "$f" >&2; done
        printf '\n' >&2
        return 1
    fi

    t32::ok "Сервер готов."
    return 0
}
