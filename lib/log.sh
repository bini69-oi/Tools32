#!/usr/bin/env bash
# Логи: на экран с цветом, в файл — без.

T32_COLOR=1
[[ -t 1 ]] || T32_COLOR=0
[[ -n "${NO_COLOR:-}" ]] && T32_COLOR=0

t32::log::__paint() {
    local code="$1" text="$2"
    if [[ $T32_COLOR -eq 1 ]]; then
        printf '\033[%sm%s\033[0m' "$code" "$text"
    else
        printf '%s' "$text"
    fi
}

t32::log::__write() {
    local level="$1" msg="$2"
    local dir; dir="$(dirname -- "$T32_LOG_FILE")"
    [[ -d $dir ]] || mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$level" "$msg" \
        >>"$T32_LOG_FILE" 2>/dev/null || true
}

t32::info()  { t32::log::__paint '0;36' '  ·  '; printf '%s\n' "$*"; t32::log::__write INFO "$*"; }
t32::ok()    { t32::log::__paint '0;32' '  ✓  '; printf '%s\n' "$*"; t32::log::__write OK "$*"; }
t32::warn()  { t32::log::__paint '0;33' '  !  '; printf '%s\n' "$*" >&2; t32::log::__write WARN "$*"; }
t32::err()   { t32::log::__paint '0;31' '  ✗  '; printf '%s\n' "$*" >&2; t32::log::__write ERROR "$*"; }
t32::step()  { printf '\n'; t32::log::__paint '1;37' "$*"; printf '\n'; t32::log::__write STEP "$*"; }

# t32::die <код> <сообщение> — осознанный выход без стека ловушки.
t32::die() {
    local code="$1"; shift
    t32::err "$*"
    if declare -F t32::journal::rollback >/dev/null; then
        t32::journal::rollback
    fi
    exit "$code"
}
