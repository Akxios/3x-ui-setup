#!/usr/bin/env bash

install_www_placeholder() {
    local index_file="$WEB_ROOT/index.html"
    local managed=false legacy_file staged

    mkdir -p "$WEB_ROOT"
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
    local snapshot="" snapshot_existed=false
    if bool_enabled "$auto_https" && bool_enabled "$use_https"; then
        fail "Нельзя одновременно включать NGINX_AUTO_HTTPS и NGINX_USE_HTTPS"
    fi

    install_packages_if_missing nginx
    nginx_site_guard
    install_www_placeholder

    if bool_enabled "$use_https" && [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
        fail "NGINX_USE_HTTPS=true, но файлы сертификата не найдены"
    fi

    if bool_enabled "$auto_https"; then
        [[ -n "${LETSENCRYPT_EMAIL:-}" ]] || fail "LETSENCRYPT_EMAIL не задан"
        install_packages_if_missing certbot
        if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
            # A first certificate needs an HTTP challenge endpoint. The existing
            # managed site remains available for rollback if Certbot fails.
            snapshot="$(mktemp)"
            if [[ -f "${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}" ]]; then
                cp -p "${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}" "$snapshot"
                snapshot_existed=true
            fi
            nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl"
        else
            # On repeats, keep serving working HTTPS throughout renewal.
            nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"
        fi
        local domains=(-d "$DOMAIN")
        if bool_enabled "${ENABLE_WWW:-false}"; then
            domains+=(-d "www.${DOMAIN}")
        fi
        if ! certbot certonly --webroot -w "$WEB_ROOT" --non-interactive \
            --agree-tos --email "$LETSENCRYPT_EMAIL" --keep-until-expiring \
            --deploy-hook "systemctl reload nginx" "${domains[@]}" >> "$LOG_FILE" 2>&1; then
            if [[ -n "${snapshot:-}" ]]; then
                nginx_restore_snapshot "$snapshot" "$snapshot_existed"
                rm -f "$snapshot"
            fi
            fail "Certbot завершился с ошибкой. Рабочий конфиг nginx сохранён; проверьте $LOG_FILE"
        fi
        if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
            if [[ -n "${snapshot:-}" ]]; then
                nginx_restore_snapshot "$snapshot" "$snapshot_existed"
                rm -f "$snapshot"
            fi
            fail "Certbot не создал ожидаемые файлы сертификата"
        fi
        if ! (nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"); then
            if [[ -n "${snapshot:-}" ]]; then
                nginx_restore_snapshot "$snapshot" "$snapshot_existed"
                rm -f "$snapshot"
            fi
            fail "Не удалось включить HTTPS-конфиг nginx"
        fi
        if [[ -n "${snapshot:-}" ]]; then rm -f "$snapshot"; fi
        summary_add "TLS: сертификат Let's Encrypt для ${DOMAIN}"
    elif bool_enabled "$use_https"; then
        nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"
    else
        nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl"
    fi

    summary_section "Nginx"
    summary_add "Сайт: ${DOMAIN}"
    summary_add "Web root: ${WEB_ROOT}"
    if bool_enabled "$auto_https" || bool_enabled "$use_https"; then
        summary_add "Сертификат: ${NGINX_CERT_PATH}"
        summary_add "Ключ: ${NGINX_CERT_KEY_PATH}"
    fi
    ok "nginx настроен для ${DOMAIN}"
}

run_nginx_module
