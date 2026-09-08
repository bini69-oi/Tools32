#!/usr/bin/env bash
# Прогон всех юнит-тестов. Каждый файл — отдельный процесс, чтобы падение
# одного (или сработавший t32::die) не уносило остальные.
set -uo pipefail

T32_TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export T32_ROOT="${T32_ROOT:-$(cd -- "$T32_TESTS_DIR/.." && pwd)}"
export T32_LOG_FILE="${TMPDIR:-/tmp}/tools32-test.log"

failed=0
for f in "$T32_TESTS_DIR"/unit/*.sh; do
    [[ -e $f ]] || continue
    printf '\n\033[1;37m%s\033[0m\n' "${f##*/}"
    bash "$f" || failed=1
done

if [[ $failed -eq 0 ]]; then
    printf '\n\033[0;32mВсе тесты прошли.\033[0m\n'
else
    printf '\n\033[0;31mЕсть провалы.\033[0m\n' >&2
fi
exit $failed
