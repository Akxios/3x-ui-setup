#!/usr/bin/env bash

bool_enabled "${INSTALL_3X_UI:-false}" || return 0
bool_enabled "${XUI_AUTO_CONFIGURE:-true}" || return 0

[[ -f "$NGINX_CERT_PATH" && -f "$NGINX_CERT_KEY_PATH" ]] || fail "Сначала настройте TLS: scripts/install.sh nginx"
log "Настройка панели и подписок через API 3x-ui"
xui_setup configure

site_file="${NGINX_SITE_DIR:-/etc/nginx/sites-available}/${DOMAIN}"
site_snapshot="$(mktemp)"
site_existed=false
if [[ -f "$site_file" ]]; then
    cp -p "$site_file" "$site_snapshot"
    site_existed=true
fi

if ! (nginx_apply_template "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl"); then
    xui_setup rollback || warn "Откат 3x-ui требует ручной проверки"
    rm -f "$site_snapshot"
    fail "Nginx-конфиг панели не применён"
fi

log "Проверка HTTPS панели и подписок"
if ! xui_setup verify; then
    nginx_restore_snapshot "$site_snapshot" "$site_existed"
    xui_setup rollback || warn "Откат 3x-ui требует ручной проверки"
    rm -f "$site_snapshot"
    fail "Проверка HTTPS панели или подписок не пройдена"
fi
rm -f "$site_snapshot"
summary_section "Доступ к 3x-ui"
summary_add "Панель и подписки: HTTPS через nginx, внешний порт 443/tcp"
summary_add "Реквизиты: ${XUI_ACCESS_FILE} (sudo bash scripts/install.sh access)"
summary_add "Проверка выполнена локально; внешний firewall провайдера не проверялся."
