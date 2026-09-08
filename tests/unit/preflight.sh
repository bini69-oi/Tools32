#!/usr/bin/env bash
# shellcheck disable=SC2016  # $T32_ROOT нарочно раскрывается в дочернем bash, не здесь
# shellcheck disable=SC2329  # стабы awk/df/ss вызываются косвенно, из проверок
# Предполётные проверки должны собирать ВСЕ проблемы, а не падать на первой.
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require journal
t32::require preflight


t32::t::case "нехватка памяти попадает в список провалов"
T32_PREFLIGHT_FAILED=(); T32_PREFLIGHT_WARNED=()
awk() { printf '512\n'; }
t32::preflight::memory 2048
unset -f awk
t32::t::eq "1" "${#T32_PREFLIGHT_FAILED[@]}"

t32::t::case "памяти впритык — это предупреждение, а не отказ"
T32_PREFLIGHT_FAILED=(); T32_PREFLIGHT_WARNED=()
awk() { printf '2048\n'; }
t32::preflight::memory 2048
unset -f awk
t32::t::eq "0 1" "${#T32_PREFLIGHT_FAILED[@]} ${#T32_PREFLIGHT_WARNED[@]}"

t32::t::case "памяти с запасом — тишина"
T32_PREFLIGHT_FAILED=(); T32_PREFLIGHT_WARNED=()
awk() { printf '8192\n'; }
t32::preflight::memory 2048
unset -f awk
t32::t::eq "0 0" "${#T32_PREFLIGHT_FAILED[@]} ${#T32_PREFLIGHT_WARNED[@]}"

t32::t::case "мало места на диске — отказ"
T32_PREFLIGHT_FAILED=()
df() { printf 'Avail\n5G\n'; }
t32::preflight::disk 20 /
unset -f df
t32::t::eq "1" "${#T32_PREFLIGHT_FAILED[@]}"

t32::t::case "места хватает — тишина"
T32_PREFLIGHT_FAILED=()
df() { printf 'Avail\n60G\n'; }
t32::preflight::disk 20 /
unset -f df
t32::t::eq "0" "${#T32_PREFLIGHT_FAILED[@]}"

t32::t::case "сообщение о занятом порте называет процесс"
T32_PREFLIGHT_FAILED=()
ss() { printf 'LISTEN 0 511 *:443 *:* users:(("nginx",pid=1,fd=6))\n'; }
t32::preflight::port 443
unset -f ss
t32::t::contains "nginx" "${T32_PREFLIGHT_FAILED[0]:-}"

t32::t::case "несколько проблем копятся, а не обрываются на первой"
T32_PREFLIGHT_FAILED=()
awk() { printf '256\n'; }
df() { printf 'Avail\n1G\n'; }
t32::preflight::memory 2048
t32::preflight::disk 20 /
unset -f awk df
t32::t::eq "2" "${#T32_PREFLIGHT_FAILED[@]}"

t32::t::case "неизвестная роль отвергается"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require journal; t32::require preflight; t32::preflight::run хрень'

t32::t::summary
