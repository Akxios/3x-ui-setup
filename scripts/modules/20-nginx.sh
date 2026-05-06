#!/usr/bin/env bash

run_nginx_module() {
    bool_enabled "${ENABLE_NGINX:-true}" || {
        warn "Модуль nginx отключён"
        return 0
    }

    log "Настройка nginx-заглушки"

    local auto_https="${NGINX_AUTO_HTTPS:-true}"
    local use_https="${NGINX_USE_HTTPS:-false}"

    if bool_enabled "$auto_https" && bool_enabled "$use_https"; then
        fail "Нельзя одновременно включать NGINX_AUTO_HTTPS и NGINX_USE_HTTPS"
    fi

    install_packages_if_missing nginx

    issue_letsencrypt_cert() {
        local domains=("-d" "$DOMAIN")

        if bool_enabled "${ENABLE_WWW:-false}"; then
            domains+=("-d" "www.${DOMAIN}")
        fi

        if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
            fail "LETSENCRYPT_EMAIL пустой. Укажите его в .env для автоматического HTTPS."
        fi

        install_packages_if_missing certbot

        certbot certonly \
            --webroot -w "$WEB_ROOT" \
            --non-interactive --agree-tos \
            --email "$LETSENCRYPT_EMAIL" \
            --keep-until-expiring \
            "${domains[@]}"

        ok "Сертификат Let's Encrypt выпущен/проверен"
    }

    mkdir -p "$WEB_ROOT"

    render_template \
        "${PROJECT_DIR}/templates/www/index.html.tpl" \
        "${WEB_ROOT}/index.html"

    local site_file="/etc/nginx/sites-available/${DOMAIN}"
    local enabled_file="/etc/nginx/sites-enabled/${DOMAIN}"

    backup_file "$site_file"

    if bool_enabled "$auto_https"; then
        render_template \
            "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl" \
            "$site_file"

        ln -sf "$site_file" "$enabled_file"

        if [[ -e /etc/nginx/sites-enabled/default ]]; then
            rm -f /etc/nginx/sites-enabled/default
        fi

        nginx -t
        systemctl reload nginx || systemctl restart nginx

        issue_letsencrypt_cert

        render_template \
            "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl" \
            "$site_file"

    elif bool_enabled "$use_https"; then
        if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
            fail "NGINX_USE_HTTPS=true, но файлы сертификата не найдены"
        fi

        render_template \
            "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl" \
            "$site_file"

    else
        render_template \
            "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl" \
            "$site_file"
    fi

    ln -sf "$site_file" "$enabled_file"

    if [[ -e /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
    fi

    nginx -t
    systemctl reload nginx || systemctl restart nginx

    ok "nginx настроен для ${DOMAIN}"
}

run_nginx_module
