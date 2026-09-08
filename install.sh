#!/usr/bin/env bash
# Tools32 — установка и обслуживание Remnawave (панель, ноды, реверс-прокси).
# https://github.com/bini69-oi/Tools32

T32_VERSION="0.1.0"

T32_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/boot.sh
source "$T32_ROOT/lib/boot.sh"

t32::require log
t32::require journal
t32::require versions
t32::require preflight

t32::usage() {
    cat <<USAGE
Tools32 $T32_VERSION — Remnawave на своём сервере.

  install.sh check [роль] [домен...]   проверить сервер перед установкой
  install.sh versions                  показать, какие образы будут поставлены
  install.sh version                   версия скрипта
  install.sh help                      эта справка

  роль: panel | node | panel-node (по умолчанию panel-node)

Примеры:
  bash install.sh check panel panel.example.com sub.example.com
  bash install.sh check node node.example.com
USAGE
}

t32::main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        check)
            local role="${1:-panel-node}"; shift || true
            t32::preflight::run "$role" "$@"
            ;;
        versions)
            t32::step "Образы для панели ${T32_PANEL_MAJOR}.x"
            t32::versions::print
            ;;
        version)
            printf 'Tools32 %s\n' "$T32_VERSION"
            ;;
        help|-h|--help)
            t32::usage
            ;;
        *)
            t32::err "Неизвестная команда: '$cmd'"
            printf '\n'
            t32::usage
            return 64
            ;;
    esac
}

t32::main "$@"
