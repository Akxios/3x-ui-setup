#!/usr/bin/env bash

bool_enabled "${ENABLE_FAIL2BAN:-true}" || {
    warn "Fail2Ban module disabled"
    return 0
}

log "Configuring Fail2Ban"

install_packages_if_missing fail2ban

backup_file /etc/fail2ban/jail.local

render_template \
    "${PROJECT_DIR}/templates/fail2ban/jail.local.tpl" \
    "/etc/fail2ban/jail.local"

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 2

fail2ban-client ping || true
fail2ban-client status || true

ok "Fail2Ban configured"
