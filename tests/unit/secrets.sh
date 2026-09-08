#!/usr/bin/env bash
# shellcheck disable=SC2016  # $T32_ROOT нарочно раскрывается в дочернем bash, не здесь
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require secrets

t32::t::case "пароль ровно заказанной длины"
p="$(t32::secrets::password 24)"
t32::t::eq "24" "${#p}"

t32::t::case "длина держится и на коротком, и на длинном пароле"
short="$(t32::secrets::password 8)"; long="$(t32::secrets::password 64)"
t32::t::eq "8 64" "${#short} ${#long}"

# Апстримовский head /dev/urandom | tr -dc … иногда отдаёт меньше символов,
# чем просили. Сто прогонов подряд ловят такое надёжно.
t32::t::case "сто паролей подряд — и ни один не короче"
bad=0
for _ in $(seq 1 100); do
    p="$(t32::secrets::password 24)"
    [[ ${#p} -ne 24 ]] && bad=$((bad + 1))
done
t32::t::eq "0" "$bad"

t32::t::case "в пароле есть все четыре класса символов"
missing=0
for _ in $(seq 1 50); do
    p="$(t32::secrets::password 16)"
    [[ $p =~ [A-Z] ]] || missing=$((missing + 1))
    [[ $p =~ [a-z] ]] || missing=$((missing + 1))
    [[ $p =~ [0-9] ]] || missing=$((missing + 1))
    [[ $p =~ [\!@#\%^\&\*\(\)_+-] ]] || missing=$((missing + 1))
done
t32::t::eq "0" "$missing"

t32::t::case "два пароля подряд не совпадают"
a="$(t32::secrets::password 24)"; b="$(t32::secrets::password 24)"
if [[ $a == "$b" ]]; then t32::t::__fail "генератор повторился"; else t32::t::__pass; fi

t32::t::case "логин начинается с буквы и состоит из букв и цифр"
u="$(t32::secrets::username 12)"
if [[ $u =~ ^[a-z][A-Za-z0-9]{11}$ ]]; then t32::t::__pass; else t32::t::__fail "получилось «$u»"; fi

t32::t::case "hex-ключ вдвое длиннее числа байт"
h="$(t32::secrets::hex 32)"
t32::t::eq "64" "${#h}"

t32::t::case "hex-ключ — это действительно hex"
if [[ $h =~ ^[0-9a-f]+$ ]]; then t32::t::__pass; else t32::t::__fail "не hex: $h"; fi

t32::t::case "слишком короткий пароль не генерируем"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require secrets; t32::secrets::password 4'

t32::t::summary
