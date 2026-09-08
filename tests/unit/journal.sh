#!/usr/bin/env bash
# Откат обязан снести ровно то, что создал, и ни байтом больше.
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require journal

T32_STATE_DIR="$(mktemp -d)"
trap 'rm -rf "$T32_STATE_DIR" "${SANDBOX:-}"' EXIT

t32::t::case "корень не считается безопасным для удаления"
t32::t::fails t32::journal::__path_is_safe "/"

t32::t::case "/opt целиком не считается безопасным"
t32::t::fails t32::journal::__path_is_safe "/opt"

t32::t::case "относительный путь не считается безопасным"
t32::t::fails t32::journal::__path_is_safe "opt/remnawave"

t32::t::case "путь с .. не считается безопасным"
t32::t::fails t32::journal::__path_is_safe "/opt/remnawave/../../etc"

t32::t::case "/opt/remnawave удалять можно"
t32::t::ok t32::journal::__path_is_safe "/opt/remnawave"

SANDBOX="$(mktemp -d)"
t32::t::case "откат сносит созданный каталог"
t32::journal::open "тест"
t32::journal::mkdir "$SANDBOX/deep/remnawave"
t32::journal::rollback
t32::t::dir_gone "$SANDBOX/deep/remnawave"

t32::t::case "commit отключает откат"
t32::journal::open "тест"
t32::journal::mkdir "$SANDBOX/deep/keepme"
t32::journal::commit
t32::journal::rollback
t32::t::dir_exists "$SANDBOX/deep/keepme"

t32::t::case "существовавший ранее каталог в журнал не попадает"
mkdir -p "$SANDBOX/deep/pre-existing"
t32::journal::open "тест"
t32::journal::mkdir "$SANDBOX/deep/pre-existing"
t32::journal::rollback
t32::t::dir_exists "$SANDBOX/deep/pre-existing"

t32::t::summary
