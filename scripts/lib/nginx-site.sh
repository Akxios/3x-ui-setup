#!/usr/bin/env bash

# Only manage a site created by this project. A manually maintained vhost
# needs an explicit migration, not an automatic overwrite.
nginx_site_guard() {
    local site_file="${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}"
    local enabled_file="${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}"
    if [[ -e "$site_file" || -L "$site_file" ]]; then
        [[ -f "$site_file" && ! -L "$site_file" ]] || fail "Некорректный или символьный nginx-конфиг: $site_file"
        grep -qx '# Managed by 3x-ui-setup' "$site_file" || fail "Nginx-конфиг $site_file не создан этим проектом; автоматическая замена запрещена"
    fi
    if [[ -e "$enabled_file" || -L "$enabled_file" ]]; then
        [[ -L "$enabled_file" && "$(readlink "$enabled_file")" == "$site_file" ]] || fail "Nginx symlink $enabled_file занят другим сайтом"
    fi
}

nginx_apply_template() {
    local template="$1"
    local site_file="${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}"
    local enabled_file="${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}"
    local staged backup had_site=false had_link=false
    mkdir -p "${NGINX_SITE_DIR:-/etc/nginx/sites-available}" "${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}"
    nginx_site_guard
    staged="$(mktemp "${NGINX_SITE_DIR:-/etc/nginx/sites-available}/.${DOMAIN}.XXXXXX")"
    backup="$(mktemp)"
    if [[ -f "$site_file" ]]; then
        cp -p "$site_file" "$backup"
        had_site=true
    fi
    [[ -L "$enabled_file" ]] && had_link=true
    if ! (render_template "$template" "$staged"); then
        rm -f "$staged" "$backup"
        fail "Не удалось подготовить nginx-конфиг"
    fi
    chmod 644 "$staged"
    mv -f "$staged" "$site_file"
    ln -sfn "$site_file" "$enabled_file"

    if nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1; then
        rm -f "$backup"
        ok "nginx-конфиг проверен и применён"
        return 0
    fi

    if [[ "$had_site" == true ]]; then
        cp -p "$backup" "$site_file"
    else
        rm -f "$site_file"
    fi
    if [[ "$had_link" == false ]]; then
        rm -f "$enabled_file"
    fi
    rm -f "$backup"
    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1 || warn "Не удалось перезагрузить nginx после отката"
    fail "nginx не принял новый конфиг; предыдущая конфигурация восстановлена"
}

nginx_restore_snapshot() {
    local snapshot="$1"
    local existed="$2"
    local site_file="${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}"
    local enabled_file="${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}/${DOMAIN}"
    if [[ "$existed" == true ]]; then
        cp -p "$snapshot" "$site_file"
        ln -sfn "$site_file" "$enabled_file"
    else
        rm -f "$site_file" "$enabled_file"
    fi
    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1 || warn "После отката nginx требует ручной проверки"
}
