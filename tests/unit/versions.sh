#!/usr/bin/env bash
# shellcheck disable=SC2016  # $T32_ROOT нарочно раскрывается в дочернем bash, не здесь
# Реестр версий: главная защита от бага, из-за которого апстрим развёл
# subscription-page и панель по разным мажорам в разных путях установки.
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require versions

t32::t::case "по умолчанию стоит панель 3.x"
t32::t::eq "3" "$T32_PANEL_MAJOR"

t32::t::case "backend взят из реестра, а не :latest"
t32::t::contains "remnawave/backend:3.4.3" "$(t32::versions::image backend)"

t32::t::case "страница подписки под 3.x — это 8.x"
t32::t::contains "subscription-page:8" "$(t32::versions::image subscription-page)"

t32::t::case "переключение на 2.x двигает И панель, И страницу подписки"
t32::versions::apply_major 2
t32::t::eq "remnawave/backend:2 remnawave/subscription-page:7.2.6" \
    "$(t32::versions::image backend) $(t32::versions::image subscription-page)"

t32::t::case "возврат на 3.x возвращает обе"
t32::versions::apply_major 3
t32::t::eq "remnawave/backend:3.4.3 remnawave/subscription-page:8.0.0" \
    "$(t32::versions::image backend) $(t32::versions::image subscription-page)"

t32::t::case "ни один образ не приколочен к плавающему тегу"
floating=""
for key in "${!T32_IMAGE[@]}"; do
    case "${T32_IMAGE[$key]}" in
        *:latest|*:dev|*:main) floating+="$key " ;;
    esac
done
t32::t::eq "" "$floating"

t32::t::case "опечатка в имени образа не проходит молча"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require versions; t32::versions::image backemd'

t32::t::case "неизвестный мажор панели не проходит молча"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require versions; t32::versions::apply_major 9'

t32::t::summary
