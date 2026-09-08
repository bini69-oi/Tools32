#!/usr/bin/env bash
# Журнал отката: каждый шаг записывает, что он создал, и при падении
# установка разбирается в обратном порядке.
#
# Апстрим этого не умеет: если установка панели падает на середине, на сервере
# остаются каталоги /opt/remnawave, поднятые контейнеры и правила ufw, а
# повторный запуск натыкается на них и падает уже по другой причине.

t32::journal::__file() { printf '%s/journal.tsv' "$T32_STATE_DIR"; }

# t32::journal::open <операция> — начать новый журнал.
t32::journal::open() {
    local op="$1"
    mkdir -p "$T32_STATE_DIR"
    chmod 700 "$T32_STATE_DIR"
    T32_JOURNAL_OP="$op"
    T32_JOURNAL_ACTIVE=1
    printf '# %s\t%s\n' "$op" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$(t32::journal::__file)"
}

# t32::journal::record <тип> <аргумент> — запомнить созданное.
# Типы: dir, file, compose, systemd, ufw, cron, docker-net
t32::journal::record() {
    [[ ${T32_JOURNAL_ACTIVE:-0} -eq 1 ]] || return 0
    printf '%s\t%s\n' "$1" "$2" >>"$(t32::journal::__file)"
}

# t32::journal::commit — установка дошла до конца, откатывать нечего.
t32::journal::commit() {
    T32_JOURNAL_ACTIVE=0
    local f; f="$(t32::journal::__file)"
    [[ -f $f ]] && mv -f "$f" "${f%.tsv}.done.tsv"
    return 0
}

# Не даём откату снести корень, /opt целиком или домашний каталог.
t32::journal::__path_is_safe() {
    local p="$1"
    [[ $p == /* ]] || return 1
    [[ $p == *".."* ]] && return 1
    case "$p" in
        /|/opt|/etc|/var|/usr|/root|/home|/var/lib|/var/log) return 1 ;;
    esac
    # Минимум два уровня вложенности: /opt/remnawave — да, /opt — нет.
    [[ $(tr -cd '/' <<<"$p" | wc -c) -ge 2 ]] || return 1
    return 0
}

t32::journal::__undo() {
    local kind="$1" arg="$2"
    case "$kind" in
        compose)
            if [[ -f "$arg/docker-compose.yml" ]]; then
                (cd "$arg" && docker compose down -v --remove-orphans >/dev/null 2>&1) || true
            fi
            ;;
        systemd)
            systemctl stop "$arg" >/dev/null 2>&1 || true
            systemctl disable "$arg" >/dev/null 2>&1 || true
            ;;
        ufw)
            ufw --force delete "$arg" >/dev/null 2>&1 || true
            ;;
        cron)
            (crontab -l 2>/dev/null | grep -vF "$arg" | crontab -) >/dev/null 2>&1 || true
            ;;
        docker-net)
            docker network rm "$arg" >/dev/null 2>&1 || true
            ;;
        file)
            t32::journal::__path_is_safe "$arg" && rm -f -- "$arg"
            ;;
        dir)
            t32::journal::__path_is_safe "$arg" && rm -rf -- "$arg"
            ;;
        *)
            return 0
            ;;
    esac
}

# t32::journal::rollback — разобрать всё, что успели создать.
t32::journal::rollback() {
    local f; f="$(t32::journal::__file)"
    [[ ${T32_JOURNAL_ACTIVE:-0} -eq 1 && -s $f ]] || return 0
    T32_JOURNAL_ACTIVE=0

    printf '\n' >&2
    t32::warn "Откатываю «${T32_JOURNAL_OP:-установку}» — сервер вернётся в исходное состояние."

    # Журнал читаем целиком и идём по нему с конца — разбирать надо в порядке,
    # обратном созданию. Без tac нарочно: он есть в GNU coreutils, но не везде,
    # а откат, который молча ничего не сделал из-за отсутствующей утилиты, — это
    # ровно тот отказ, ради которого журнал и заводился.
    local -a lines=()
    mapfile -t lines <"$f"

    local i kind arg
    for ((i = ${#lines[@]} - 1; i >= 0; i--)); do
        [[ -z ${lines[i]} || ${lines[i]} == '#'* ]] && continue
        IFS=$'\t' read -r kind arg <<<"${lines[i]}"
        [[ -z ${kind:-} ]] && continue
        t32::info "откат: $kind $arg"
        t32::journal::__undo "$kind" "$arg" || true
    done

    mv -f "$f" "${f%.tsv}.rolled-back.tsv" 2>/dev/null || true
    t32::ok "Откат закончен. Лог: $T32_LOG_FILE"
}

# Обёртки: делают дело и сразу пишут в журнал.
t32::journal::mkdir() {
    local d="$1"
    [[ -d $d ]] || { mkdir -p "$d"; t32::journal::record dir "$d"; }
}
