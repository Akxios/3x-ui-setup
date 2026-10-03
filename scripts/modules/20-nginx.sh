#!/usr/bin/env bash

prepare_webroot_directories() {
    local path="$WEB_ROOT"
    local -a missing=()
    local i
    [[ "$path" == /* && "$path" != / ]] || fail "WEB_ROOT должен быть абсолютным каталогом, отличным от /"
    while [[ ! -d "$path" ]]; do
        [[ ! -e "$path" && ! -L "$path" ]] || fail "WEB_ROOT содержит не каталог: $path"
        missing+=("$path")
        path="$(dirname "$path")"
    done
    for ((i=${#missing[@]}-1; i>=0; i--)); do
        mkdir -m 755 -- "${missing[i]}" || fail "Не удалось создать каталог сайта: ${missing[i]}"
    done
}

prepare_acme_directories() {
    local path index_file="$WEB_ROOT/index.html" repair_managed=false
    # Earlier project versions created these directories with umask 077.
    # Repair only the known default layout and a page marked as ours.
    if [[ "$WEB_ROOT" == "/var/www/${DOMAIN}/html" && -f "$index_file" && ! -L "$index_file" ]] &&
        [[ "$(sed -n '2p' "$index_file")" == '<!-- Managed by 3x-ui-setup -->' ]]; then
        repair_managed=true
        for path in "/var/www/${DOMAIN}" "$WEB_ROOT"; do
            [[ -d "$path" && ! -L "$path" ]] || fail "Каталог сайта является символьной ссылкой: $path"
            chmod 755 "$path" || fail "Не удалось открыть nginx доступ к каталогу: $path"
        done
    fi

    for path in "$WEB_ROOT/.well-known" "$WEB_ROOT/.well-known/acme-challenge"; do
        if [[ -e "$path" || -L "$path" ]]; then
            [[ -d "$path" && ! -L "$path" ]] || fail "Каталог ACME является символьной ссылкой или файлом: $path"
            if [[ "$repair_managed" == true ]]; then
                chmod 755 "$path" || fail "Не удалось открыть nginx доступ к каталогу: $path"
            fi
        else
            mkdir -m 755 -- "$path" || fail "Не удалось создать каталог ACME: $path"
        fi
    done
}

verify_acme_http_route() {
    local challenge_dir="$WEB_ROOT/.well-known/acme-challenge"
    local probe response url enabled_file domain address attempt served
    local -a domains=("$DOMAIN") addresses=(127.0.0.1)
    if bool_enabled "${ENABLE_WWW:-false}"; then
        domains+=("www.${DOMAIN}")
    fi
    if [[ -r /proc/net/if_inet6 ]] && grep -q . /proc/net/if_inet6; then
        addresses+=("[::1]")
    fi
    enabled_file="${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}"
    if ! nginx_site_loaded; then
        fail "Nginx не загрузил конфиг сайта ${enabled_file}. Проверьте include sites-enabled в nginx.conf"
    fi
    probe="$(mktemp "$challenge_dir/setup-XXXXXXXX")"
    printf '%s\n' "${probe##*/}" > "$probe"
    chmod 644 "$probe"
    for domain in "${domains[@]}"; do
        url="http://${domain}/.well-known/acme-challenge/${probe##*/}"
        for address in "${addresses[@]}"; do
            served=false
            # nginx reload returns before every worker has necessarily switched
            # to the new vhost, so allow a short convergence window.
            for attempt in 1 2 3 4 5; do
                if response="$(curl --noproxy '*' --silent --show-error --fail --connect-timeout 2 --max-time 3 \
                    --resolve "${domain}:80:${address}" "$url" 2>> "$LOG_FILE")" &&
                    [[ "$response" == "${probe##*/}" ]]; then
                    served=true
                    break
                fi
                sleep 0.2
            done
            if [[ "$served" != true ]]; then
                if [[ -f /var/log/nginx/error.log ]]; then
                    grep -F "${probe##*/}" /var/log/nginx/error.log | tail -n 3 >&2 || :
                fi
                warn "Проверочный файл: $probe (права пути: namei -l '$probe')"
                rm -f "$probe"
                fail "Nginx не отдаёт ACME-файл для ${domain} через ${address}:80. Проверьте server_name, IPv6 и права WEB_ROOT; Certbot не запускался"
            fi
        done
    done
    rm -f "$probe"
}

install_www_placeholder() {
    local index_file="$WEB_ROOT/index.html"
    local managed=false legacy_file staged

    prepare_webroot_directories
    if [[ -e "$index_file" || -L "$index_file" ]]; then
        [[ -f "$index_file" && ! -L "$index_file" ]] || fail "Некорректный или символьный файл сайта: $index_file"
        if [[ "$(sed -n '2p' "$index_file")" == '<!-- Managed by 3x-ui-setup -->' ]]; then
            managed=true
        else
            legacy_file="$(mktemp "$WEB_ROOT/.index-legacy.XXXXXX")"
            if ! render_template "${PROJECT_DIR}/templates/www/index.legacy.html.tpl" "$legacy_file"; then
                rm -f "$legacy_file"
                fail "Не удалось проверить прежнюю страницу сайта"
            fi
            if cmp -s "$legacy_file" "$index_file"; then managed=true; fi
            rm -f "$legacy_file"
        fi
    else
        managed=true
    fi

    if [[ "$managed" == true ]]; then
        staged="$(mktemp "$WEB_ROOT/.index-new.XXXXXX")"
        if ! render_template "${PROJECT_DIR}/templates/www/index.html.tpl" "$staged"; then
            rm -f "$staged"
            fail "Не удалось подготовить страницу сайта"
        fi
        if ! cmp -s "$staged" "$index_file"; then
            chmod 644 "$staged"
            mv -f "$staged" "$index_file"
        else
            rm -f "$staged"
        fi
    fi
}

run_nginx_module() {
    bool_enabled "${ENABLE_NGINX:-true}" || {
        warn "Модуль nginx отключён"
        return 0
    }
    log "Настройка nginx и HTTPS"
    local auto_https="${NGINX_AUTO_HTTPS:-true}"
    local use_https="${NGINX_USE_HTTPS:-false}"
    local snapshot="" snapshot_existed=false snapshot_enabled=false
    if bool_enabled "$auto_https" && bool_enabled "$use_https"; then
        fail "Нельзя одновременно включать NGINX_AUTO_HTTPS и NGINX_USE_HTTPS"
    fi

    install_packages_if_missing nginx curl
    nginx_site_guard
    install_www_placeholder

    if bool_enabled "$use_https" && [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
        fail "NGINX_USE_HTTPS=true, но файлы сертификата не найдены"
    fi

    if bool_enabled "$auto_https"; then
        [[ -n "${LETSENCRYPT_EMAIL:-}" ]] || fail "LETSENCRYPT_EMAIL не задан"
        install_packages_if_missing certbot
        prepare_acme_directories
        snapshot="$(mktemp)"
        if [[ -f "${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}" ]]; then
            cp -p "${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}" "$snapshot"
            snapshot_existed=true
        fi
        if [[ -L "${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}" ]]; then
            snapshot_enabled=true
        fi
        if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
            # A first certificate needs an HTTP challenge endpoint. The existing
            # managed site remains available for rollback if Certbot fails.
            if ! (nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl"); then
                rm -f "$snapshot"
                fail "Не удалось применить HTTP-конфиг nginx для Certbot"
            fi
        else
            # On repeats, keep serving working HTTPS throughout renewal.
            if ! (nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"); then
                rm -f "$snapshot"
                fail "Не удалось применить HTTPS-конфиг nginx"
            fi
        fi
        if ! (verify_acme_http_route); then
            nginx_restore_snapshot "$snapshot" "$snapshot_existed" "$snapshot_enabled"
            rm -f "$snapshot"
            fail "Проверка HTTP-маршрута для Certbot не пройдена; сертификат не запрашивался"
        fi
        local domains=(-d "$DOMAIN")
        if bool_enabled "${ENABLE_WWW:-false}"; then
            domains+=(-d "www.${DOMAIN}")
        fi
        if ! certbot certonly --webroot -w "$WEB_ROOT" --non-interactive \
            --agree-tos --email "$LETSENCRYPT_EMAIL" --keep-until-expiring \
            --deploy-hook "nginx -t && systemctl reload nginx" "${domains[@]}" >> "$LOG_FILE" 2>&1; then
            nginx_restore_snapshot "$snapshot" "$snapshot_existed" "$snapshot_enabled"
            rm -f "$snapshot"
            fail "Certbot не подтвердил домен. Проверьте A/AAAA, внешний доступ на 80/tcp и ответ HTTP для /.well-known/acme-challenge/; рабочий nginx-конфиг сохранён. Лог: $LOG_FILE"
        fi
        if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
            nginx_restore_snapshot "$snapshot" "$snapshot_existed" "$snapshot_enabled"
            rm -f "$snapshot"
            fail "Certbot не создал ожидаемые файлы сертификата"
        fi
        if ! (nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"); then
            nginx_restore_snapshot "$snapshot" "$snapshot_existed" "$snapshot_enabled"
            rm -f "$snapshot"
            fail "Не удалось включить HTTPS-конфиг nginx"
        fi
        rm -f "$snapshot"
        summary_add "TLS: сертификат Let's Encrypt для ${DOMAIN}"
    elif bool_enabled "$use_https"; then
        nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"
    else
        nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl"
    fi

    summary_section "Nginx"
    summary_add "Сайт: ${DOMAIN}"
    summary_add "Nginx available: ${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}"
    summary_add "Nginx enabled: ${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}"
    summary_add "Web root: ${WEB_ROOT}"
    if bool_enabled "$auto_https" || bool_enabled "$use_https"; then
        summary_add "Сертификат: ${NGINX_CERT_PATH}"
        summary_add "Ключ: ${NGINX_CERT_KEY_PATH}"
    fi
    ok "nginx настроен для ${DOMAIN}"
}

run_nginx_module
