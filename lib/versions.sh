#!/usr/bin/env bash
# Единый реестр версий образов — один источник правды на все схемы установки.
#
# Зачем отдельным файлом: в апстриме теги прописаны прямо в шести почти
# одинаковых compose-шаблонах. Из-за этого фикс «subscription-page 8.0.0 под
# панель 3.x» (коммит 83a2db2) попал только в src/nginx/install_panel.sh, а три
# остальных пути установки продолжили тянуть :latest. Здесь такое невозможно:
# тег объявлен один раз, шаблон его подставляет.
#
# Проверено 08.09.2026 по Docker Hub — все теги существуют.

# Мажор панели, под который собран этот релиз скрипта.
T32_PANEL_MAJOR="${T32_PANEL_MAJOR:-3}"

declare -gA T32_IMAGE=(
    [backend]="remnawave/backend:3.4.3"
    [node]="remnawave/node:3.4.1"
    [subscription-page]="remnawave/subscription-page:8.0.0"
    [db]="postgres:18.6"
    [redis]="valkey/valkey:9.1.2-alpine"
    [caddy]="caddy:2.11.4"
    [nginx]="nginx:1.30"
)

# Панель 2.x отдаёт клиентам контракт 2.x, панель 3.x — 3.x, и страница
# подписки жёстко привязана к контракту. Пара «панель ↔ страница» задана здесь,
# чтобы её нельзя было расцепить правкой одного шаблона.
declare -gA T32_PANEL_PAIR=(
    [2]="remnawave/backend:2 remnawave/subscription-page:7.2.6"
    [3]="remnawave/backend:3.4.3 remnawave/subscription-page:8.0.0"
)

# t32::versions::apply_major <2|3> — переключить набор образов на мажор панели.
t32::versions::apply_major() {
    local major="$1" pair
    pair="${T32_PANEL_PAIR[$major]:-}"
    if [[ -z $pair ]]; then
        t32::die 64 "Неизвестный мажор панели: '$major'. Поддерживаются: ${!T32_PANEL_PAIR[*]}"
    fi
    T32_PANEL_MAJOR="$major"
    T32_IMAGE[backend]="${pair%% *}"
    T32_IMAGE[subscription-page]="${pair##* }"
}

# t32::versions::image <ключ> — тег образа; падает на опечатке в имени.
t32::versions::image() {
    local key="$1"
    if [[ -z ${T32_IMAGE[$key]:-} ]]; then
        t32::die 64 "Нет образа с ключом '$key'. Есть: ${!T32_IMAGE[*]}"
    fi
    printf '%s' "${T32_IMAGE[$key]}"
}

# t32::versions::print — что именно будет установлено.
t32::versions::print() {
    local key
    for key in backend node subscription-page db redis nginx caddy; do
        printf '  %-18s %s\n' "$key" "${T32_IMAGE[$key]}"
    done
}
