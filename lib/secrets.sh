#!/usr/bin/env bash
# Генерация паролей, логинов и ключей.
#
# Апстрим собирает пароль так: `head /dev/urandom | tr -dc 'A-Za-z0-9...' | head -c N`.
# `head` без аргументов берёт первые 10 строк — то есть кусок случайных байт до
# десятого 0x0A. Сколько в нём окажется подходящих символов, заранее неизвестно:
# обычно хватает, но иногда пароль молча выходит короче заказанного, а первый
# `head -c 1` для конкретного класса может не дать ничего. Здесь длина
# гарантирована циклом, который добирает байты, пока их не хватит.

T32_SECRET_ALPHABET_ALNUM='A-Za-z0-9'
T32_SECRET_ALPHABET_FULL='A-Za-z0-9!@#%^&*()_+-'

# t32::secrets::__draw <длина> <класс> — ровно столько символов, сколько просили.
t32::secrets::__draw() {
    local want="$1" class="$2" out="" chunk
    while [[ ${#out} -lt $want ]]; do
        chunk="$(LC_ALL=C tr -dc "$class" </dev/urandom | head -c "$want" || true)"
        out+="$chunk"
    done
    printf '%s' "${out:0:want}"
}

# t32::secrets::password [длина] — пароль, в котором точно есть все четыре класса.
#
# Не «взять по символу каждого класса и перемешать»: там позиции задаёт shuf,
# а это GNU-утилита, и на системе без неё генератор упадёт. Здесь пароль
# набирается целиком из общего алфавита и перебирается, пока не окажется, что
# все классы на месте. Символы при этом равновероятны, а внешних зависимостей
# нет. Для 24 символов промах — редкость; для 8 хватает пары попыток.
t32::secrets::password() {
    local length="${1:-24}"
    if [[ $length -lt 8 ]]; then
        t32::die 64 "Пароль короче 8 символов не генерируем (просили $length)."
    fi

    local pass attempt
    for ((attempt = 0; attempt < 200; attempt++)); do
        pass="$(t32::secrets::__draw "$length" "$T32_SECRET_ALPHABET_FULL")"
        [[ $pass =~ [A-Z] ]]            || continue
        [[ $pass =~ [a-z] ]]            || continue
        [[ $pass =~ [0-9] ]]            || continue
        [[ $pass =~ [^A-Za-z0-9] ]]     || continue
        printf '%s' "$pass"
        return 0
    done
    t32::die 70 "Не удалось собрать пароль длиной $length за 200 попыток — проверь /dev/urandom."
}

# t32::secrets::username [длина] — логин: буквы и цифры, начинается с буквы.
t32::secrets::username() {
    local length="${1:-12}"
    printf '%s%s' \
        "$(t32::secrets::__draw 1 'a-z')" \
        "$(t32::secrets::__draw "$((length - 1))" "$T32_SECRET_ALPHABET_ALNUM")"
}

# t32::secrets::hex <байт> — ключ в hex, вдвое длиннее в символах.
t32::secrets::hex() {
    local bytes="${1:-32}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$bytes"
    else
        LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c "$((bytes * 2))"
        printf '\n'
    fi
}
