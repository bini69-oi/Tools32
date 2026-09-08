#!/usr/bin/env bash
# Минимальный тест-раннер без зависимостей: ни bats, ни npm — только bash.

T32_TESTS_RUN=0
T32_TESTS_FAILED=0
T32_CURRENT_TEST=""

t32::t::case() {
    T32_CURRENT_TEST="$1"
    T32_TESTS_RUN=$((T32_TESTS_RUN + 1))
}

t32::t::__fail() {
    T32_TESTS_FAILED=$((T32_TESTS_FAILED + 1))
    printf '  \033[0;31mFAIL\033[0m %s\n        %s\n' "$T32_CURRENT_TEST" "$1" >&2
}

t32::t::__pass() { printf '  \033[0;32mok\033[0m   %s\n' "$T32_CURRENT_TEST"; }

# t32::t::eq <ожидаемое> <фактическое>
t32::t::eq() {
    if [[ "$1" == "$2" ]]; then t32::t::__pass
    else t32::t::__fail "ожидалось «$1», получено «$2»"; fi
}

# t32::t::contains <подстрока> <строка>
t32::t::contains() {
    if [[ "$2" == *"$1"* ]]; then t32::t::__pass
    else t32::t::__fail "в «$2» нет «$1»"; fi
}

# t32::t::ok <команда...> — команда должна завершиться нулём
t32::t::ok() {
    if "$@" >/dev/null 2>&1; then t32::t::__pass
    else t32::t::__fail "команда упала: $*"; fi
}

# t32::t::fails <команда...> — команда должна завершиться ненулём
t32::t::fails() {
    if "$@" >/dev/null 2>&1; then t32::t::__fail "команда прошла, а должна была упасть: $*"
    else t32::t::__pass; fi
}

t32::t::summary() {
    printf '\n%d проверок, %d провалов\n' "$T32_TESTS_RUN" "$T32_TESTS_FAILED"
    [[ $T32_TESTS_FAILED -eq 0 ]]
}

# t32::t::dir_exists <путь> / t32::t::dir_gone <путь>
t32::t::dir_exists() {
    if [[ -d "$1" ]]; then t32::t::__pass; else t32::t::__fail "каталога нет: $1"; fi
}
t32::t::dir_gone() {
    if [[ -d "$1" ]]; then t32::t::__fail "каталог остался: $1"; else t32::t::__pass; fi
}
