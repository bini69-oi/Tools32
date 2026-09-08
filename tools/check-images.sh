#!/usr/bin/env bash
# Проверяет, что каждый тег из реестра версий ещё существует на Docker Hub,
# и сообщает, если у Remnawave вышла версия новее приколоченной.
#
# Апстрим держит `remnawave/backend:3` и `node:latest` — они «всегда свежие»,
# но и меняются под пользователем без предупреждения. Мы пиним точную версию,
# поэтому нужен сторож, который скажет, когда пора двигать пин.

set -euo pipefail

T32_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export T32_ROOT
# shellcheck source=../lib/boot.sh
source "$T32_ROOT/lib/boot.sh"
t32::require log
t32::require versions

hub_url() {
    local repo="$1"
    # Официальные образы живут в library/*.
    [[ $repo == */* ]] || repo="library/$repo"
    printf 'https://hub.docker.com/v2/repositories/%s' "$repo"
}

missing=0
newer=0

for key in "${!T32_IMAGE[@]}"; do
    ref="${T32_IMAGE[$key]}"
    repo="${ref%%:*}"
    tag="${ref##*:}"
    code="$(curl -fsS -o /dev/null -w '%{http_code}' -m 20 "$(hub_url "$repo")/tags/$tag" || true)"
    if [[ $code == 200 ]]; then
        t32::ok "$ref"
    else
        t32::err "$ref — тега нет на Docker Hub (HTTP $code). Установка сломается."
        missing=$((missing + 1))
    fi
done

# Отдельно смотрим, не вышла ли панель новее нашего пина.
latest="$(curl -fsS -m 20 https://api.github.com/repos/remnawave/panel/releases/latest 2>/dev/null \
    | sed -nE 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v?([^"]+)".*/\1/p' | head -1 || true)"
pinned="${T32_IMAGE[backend]##*:}"
if [[ -n $latest && $latest != "$pinned" ]]; then
    t32::warn "Панель: приколочена $pinned, у Remnawave вышла $latest — пора двигать пин в lib/versions.sh."
    newer=1
fi

if [[ $missing -gt 0 ]]; then
    t32::err "Нерабочих пинов: $missing"
    exit 1
fi
t32::ok "Все пины на месте.$([[ $newer -eq 1 ]] && printf ' Есть версия новее — см. предупреждение выше.' || true)"
