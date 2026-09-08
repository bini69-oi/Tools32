#!/usr/bin/env bash
# shellcheck disable=SC2016  # $T32_ROOT нарочно раскрывается в дочернем bash, не здесь
# Генератор compose: один источник на шесть сочетаний роли и прокси.
source "$T32_ROOT/lib/boot.sh"
source "$T32_ROOT/tests/harness.sh"
t32::require log
t32::require versions
t32::require compose

for role in panel node panel-node; do
    for proxy in nginx caddy; do
        out="$(t32::compose::render "$role" "$proxy")"

        t32::t::case "$role/$proxy: не осталось неподставленных {{ПЛЕЙСХОЛДЕРОВ}}"
        if [[ $out == *'{{'* ]]; then t32::t::__fail "нашёлся {{...}}"; else t32::t::__pass; fi

        t32::t::case "$role/$proxy: ни один образ не на плавающем теге"
        floating="$(grep -oE 'image: [^ ]+:(latest|dev|main)' <<<"$out" || true)"
        t32::t::eq "" "$floating"

        t32::t::case "$role/$proxy: есть блок services"
        t32::t::contains "services:" "$out"
    done
done

t32::t::case "роль panel не тащит ноду"
out="$(t32::compose::render panel nginx)"
if [[ $out == *"remnanode:"* ]]; then t32::t::__fail "нода попала в панель"; else t32::t::__pass; fi

t32::t::case "роль node не тащит postgres"
out="$(t32::compose::render node nginx)"
if [[ $out == *"remnawave-db:"* ]]; then t32::t::__fail "база попала в ноду"; else t32::t::__pass; fi

t32::t::case "роль panel-node тащит и панель, и ноду"
out="$(t32::compose::render panel-node nginx)"
if [[ $out == *"remnawave-db:"* && $out == *"remnanode:"* ]]; then t32::t::__pass
else t32::t::__fail "не хватает одной из половин"; fi

t32::t::case "выбор nginx не тянет caddy"
out="$(t32::compose::render panel nginx)"
if [[ $out == *"caddy"* ]]; then t32::t::__fail "caddy пролез в nginx-схему"; else t32::t::__pass; fi

t32::t::case "выбор caddy не тянет nginx"
out="$(t32::compose::render panel caddy)"
if [[ $out == *"nginx"* ]]; then t32::t::__fail "nginx пролез в caddy-схему"; else t32::t::__pass; fi

# Тот самый баг апстрима: фикс пары «панель ↔ страница подписки» доехал до
# одного пути установки из четырёх. Проверяем ВСЕ пути сразу.
t32::t::case "пара панель↔страница подписки одинакова во всех сочетаниях"
pairs=""
for role in panel panel-node; do
    for proxy in nginx caddy; do
        out="$(t32::compose::render "$role" "$proxy")"
        b="$(grep -oE 'remnawave/backend:[^ ]+' <<<"$out" | head -1)"
        s="$(grep -oE 'remnawave/subscription-page:[^ ]+' <<<"$out" | head -1)"
        pairs+="$b|$s"$'\n'
    done
done
t32::t::eq "1" "$(sort -u <<<"$pairs" | grep -c . )"

t32::t::case "переключение на панель 2.x двигает пару во всех сочетаниях"
t32::versions::apply_major 2
pairs=""
for role in panel panel-node; do
    for proxy in nginx caddy; do
        out="$(t32::compose::render "$role" "$proxy")"
        pairs+="$(grep -oE 'remnawave/(backend|subscription-page):[^ ]+' <<<"$out" | sort | tr '\n' '|')"$'\n'
    done
done
t32::versions::apply_major 3
# grep . отсекает пустую строку от хвостового \n — иначе sort -u ставит её
# первой, и head -1 возвращает пустоту вместо пары.
uniq_pairs="$(sort -u <<<"$pairs" | grep . )"
t32::t::eq "remnawave/backend:2|remnawave/subscription-page:7.2.6|" "$uniq_pairs"

t32::t::case "неизвестная роль отвергается"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require versions; t32::require compose; t32::compose::render хрень nginx'

t32::t::case "неизвестный прокси отвергается"
t32::t::fails bash -c 'source "$T32_ROOT/lib/boot.sh"; t32::require log; t32::require versions; t32::require compose; t32::compose::render panel хрень'

# Ключи volumes: и networks: есть и внутри сервисов — проверять нужно только
# верхний уровень, то есть начало строки.
t32::t::case "одинокая нода не объявляет неиспользуемую сеть"
out="$(t32::compose::render node nginx)"
if grep -q '^networks:' <<<"$out"; then t32::t::__fail "сеть объявлена, хотя все сервисы в host"; else t32::t::__pass; fi

t32::t::case "одинокая нода за nginx не объявляет пустой volumes:"
out="$(t32::compose::render node nginx)"
if grep -q '^volumes:' <<<"$out"; then t32::t::__fail "есть ключ volumes: без единого тома"; else t32::t::__pass; fi

t32::t::case "панель объявляет сеть и тома на верхнем уровне"
out="$(t32::compose::render panel nginx)"
if grep -q '^networks:' <<<"$out" && grep -q '^volumes:' <<<"$out"; then t32::t::__pass
else t32::t::__fail "не хватает networks: или volumes: на верхнем уровне"; fi

t32::t::case "нода за caddy всё же объявляет тома caddy"
out="$(t32::compose::render node caddy)"
t32::t::contains "caddy-data:" "$out"

t32::t::case "у одинокой ноды нет мёртвых якорей x-networks и x-env"
out="$(t32::compose::render node nginx)"
if [[ $out == *"x-networks:"* || $out == *"x-env:"* ]]; then
    t32::t::__fail "остались якоря, которыми никто не пользуется"
else
    t32::t::__pass
fi

t32::t::summary
