#!/usr/bin/env bash
# Строгий режим, загрузчик модулей и ловушка ошибок.
#
# Апстрим (remnawave-reverse-proxy) не включает строгий режим ни в одном файле:
# упавший шаг не останавливает установку, и сервер остаётся в полусостоянии.
# Здесь наоборот — любая непроверенная ошибка валит скрипт и запускает откат.

set -euo pipefail
IFS=$'\n\t'

# Ассоциативные массивы и ${var^^} требуют bash 4. На Debian/Ubuntu стоит 5.x,
# но скрипт могут запустить через `sh install.sh` — тогда проверка сработает.
if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Tools32: нужен bash 4 или новее. Запусти: bash install.sh" >&2
    exit 78
fi

T32_ROOT="${T32_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly T32_ROOT

# Куда пишем состояние, журнал отката и логи.
T32_STATE_DIR="${T32_STATE_DIR:-/var/lib/tools32}"
T32_LOG_FILE="${T32_LOG_FILE:-/var/log/tools32.log}"

# Загруженные модули, чтобы не сорсить дважды.
declare -A T32_LOADED=()

# t32::require <имя> — подключить lib/<имя>.sh один раз.
t32::require() {
    local name="$1" path
    [[ -n "${T32_LOADED[$name]:-}" ]] && return 0
    path="$T32_ROOT/lib/$name.sh"
    if [[ ! -r "$path" ]]; then
        echo "Tools32: модуль '$name' не найден: $path" >&2
        return 78
    fi
    T32_LOADED[$name]=1
    # shellcheck source=/dev/null
    source "$path"
}

# Куда пришла ошибка — печатаем стек, а не голое "команда не найдена".
t32::__on_err() {
    local code=$? line=${1:-?} cmd=${2:-?}
    set +e
    printf '\n[FATAL] Tools32 упал: код %d, строка %s\n        команда: %s\n' \
        "$code" "$line" "$cmd" >&2
    local i
    for ((i = 1; i < ${#FUNCNAME[@]} - 1; i++)); do
        printf '        в %s (%s:%s)\n' \
            "${FUNCNAME[$i]}" "${BASH_SOURCE[$i]##*/}" "${BASH_LINENO[$i - 1]}" >&2
    done
    if declare -F t32::journal::rollback >/dev/null; then
        t32::journal::rollback
    fi
    exit "$code"
}

trap 't32::__on_err "$LINENO" "$BASH_COMMAND"' ERR
