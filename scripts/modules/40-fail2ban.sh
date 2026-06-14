#!/usr/bin/env bash

bool_enabled "${ENABLE_FAIL2BAN:-true}" || {
    warn "Модуль Fail2Ban отключён"
    return 0
}

log "Настройка Fail2Ban"

install_packages_if_missing fail2ban

backup_file /etc/fail2ban/jail.local

render_template \
    "${PROJECT_DIR}/templates/fail2ban/jail.local.tpl" \
    "/etc/fail2ban/jail.local"

run_logged "Включение Fail2Ban" systemctl enable fail2ban
run_logged "Перезапуск Fail2Ban" systemctl restart fail2ban
sleep 2

if bool_enabled "${VERBOSE:-false}"; then
    fail2ban-client ping || true
    fail2ban-client status || true
fi

summary_section "Fail2Ban"
summary_add "Статус: включён"
summary_add "Jail: sshd, nginx-botsearch=${ENABLE_NGINX_BOTSEARCH}"
ok "Fail2Ban настроен"
