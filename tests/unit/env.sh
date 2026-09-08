#!/usr/bin/env bash
# shellcheck disable=SC2016  # $T32_ROOT нарочно раскрывается в дочернем bash, не здесь
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require journal
t32::require secrets
t32::require env

WORK="$(mktemp -d)"
T32_STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK" "$T32_STATE_DIR"' EXIT

t32::env::panel "$WORK" panel.example.com sub.example.com
ENVF="$WORK/.env"

t32::t::case "файл окружения доступен только владельцу"
# Порядок важен: у GNU stat -f это «статус файловой системы», неизвестный
# формат он печатает как ? и выходит с нулём — фолбэк тогда не срабатывает.
# BSD stat на -c честно ругается, поэтому GNU-вариант идёт первым.
t32::t::eq "600" "$(stat -c '%a' "$ENVF" 2>/dev/null || stat -f '%Lp' "$ENVF")"

t32::t::case "пароль Postgres не равен postgres"
pg="$(t32::env::get "$ENVF" POSTGRES_PASSWORD)"
if [[ $pg == "postgres" || -z $pg ]]; then t32::t::__fail "пароль по умолчанию: «$pg»"; else t32::t::__pass; fi

t32::t::case "тот же пароль стоит и в DATABASE_URL"
url="$(t32::env::get "$ENVF" DATABASE_URL)"
t32::t::contains "$pg" "$url"

t32::t::case "APP_SECRET — 128 hex-символов"
sec="$(t32::env::get "$ENVF" APP_SECRET)"
t32::t::eq "128" "${#sec}"

t32::t::case "секрет вебхука ровно 64 символа из a-zA-Z0-9"
wh="$(t32::env::get "$ENVF" WEBHOOK_SECRET_HEADER)"
if [[ $wh =~ ^[A-Za-z0-9]{64}$ ]]; then t32::t::__pass; else t32::t::__fail "получилось «$wh»"; fi

# Апстрим кладёт в репозиторий один и тот же секрет на все установки.
t32::t::case "секрет вебхука свой у каждой установки"
t32::env::panel "$WORK" panel.example.com sub.example.com
wh2="$(t32::env::get "$ENVF" WEBHOOK_SECRET_HEADER)"
if [[ $wh == "$wh2" ]]; then t32::t::__fail "секрет повторился"; else t32::t::__pass; fi

t32::t::case "домены попали куда надо"
t32::t::eq "panel.example.com sub.example.com" \
    "$(t32::env::get "$ENVF" PANEL_DOMAIN) $(t32::env::get "$ENVF" SUB_PUBLIC_DOMAIN)"

t32::t::case "set заменяет существующий ключ, а не дописывает второй"
t32::env::set "$ENVF" APP_PORT 4000
t32::t::eq "1 4000" "$(grep -c '^APP_PORT=' "$ENVF") $(t32::env::get "$ENVF" APP_PORT)"

t32::t::case "set дописывает ключ, которого не было"
t32::env::set "$ENVF" T32_NEW_KEY hello
t32::t::eq "hello" "$(t32::env::get "$ENVF" T32_NEW_KEY)"

# Токены панели содержат / и +, на которых sed молча портит строку.
t32::t::case "значение со слешами и амперсандом сохраняется дословно"
tricky='eyJhbGci/OiJIUzI1&NiIsInR5cCI6+IkpXVCJ9.a/b&c'
t32::env::set "$ENVF" REMNAWAVE_API_TOKEN "$tricky"
t32::t::eq "$tricky" "$(t32::env::get "$ENVF" REMNAWAVE_API_TOKEN)"

t32::t::case "нода получает свой ключ и порт"
NODEDIR="$(mktemp -d)"
t32::env::node "$NODEDIR" "SECRET-FROM-PANEL" 2222
t32::t::eq "SECRET-FROM-PANEL 2222" \
    "$(t32::env::get "$NODEDIR/.env" NODE_SECRET_KEY) $(t32::env::get "$NODEDIR/.env" NODE_PORT)"
rm -rf "$NODEDIR"

t32::t::case "чтение несуществующего файла — ошибка, а не пустая строка"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require journal; t32::require env; t32::env::get /nope/.env APP_PORT'

t32::t::summary
