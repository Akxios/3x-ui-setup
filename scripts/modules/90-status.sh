#!/usr/bin/env bash

log "Краткий статус системы"

service_state() {
    local service="$1"

    if systemctl is-active --quiet "$service" >/dev/null 2>&1; then
        ok "${service}: active"
    else
        warn "${service}: не active"
    fi
}

if command_exists ufw; then
    echo ""
    echo "--- UFW ---"
    ufw status | sed -n '1,20p' || true
else
    warn "ufw не установлен"
fi

echo ""
echo "--- Services ---"
service_state nginx
service_state fail2ban
service_state x-ui

summary_section "Статус"
summary_add "Проверен краткий статус сервисов."

if bool_enabled "${VERBOSE:-false}"; then
    echo ""
    echo "--- Fail2Ban ---"
    fail2ban-client status || true

    echo ""
    echo "--- nginx ---"
    nginx -t || true
    systemctl status nginx --no-pager -l || true

    echo ""
    echo "--- 3x-ui / x-ui ---"
    systemctl status x-ui --no-pager -l || true

    echo ""
    echo "--- Прослушиваемые порты ---"
    ss -tulnp || true
fi
