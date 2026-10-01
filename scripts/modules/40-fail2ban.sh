#!/usr/bin/env bash

bool_enabled "${ENABLE_FAIL2BAN:-true}" || {
    warn "Модуль Fail2Ban отключён"
    return 0
}

log "Настройка Fail2Ban"
install_packages_if_missing fail2ban python3-systemd
if ! bool_enabled "${ENABLE_NGINX:-true}"; then
    ENABLE_NGINX_BOTSEARCH=false
fi
jail_file="${FAIL2BAN_JAIL_DIR:-/etc/fail2ban/jail.d}/3x-ui-setup.local"
legacy_file="${FAIL2BAN_LEGACY_FILE:-/etc/fail2ban/jail.local}"
legacy_backup="$(mktemp)"
legacy_migrated=false
if [[ -f "$legacy_file" ]] && grep -qx '# Managed by vps-server' "$legacy_file"; then
    cp -p "$legacy_file" "$legacy_backup"
    legacy_migrated=true
fi
mkdir -p "${FAIL2BAN_JAIL_DIR:-/etc/fail2ban/jail.d}"
if [[ -e "$jail_file" || -L "$jail_file" ]]; then
    [[ -f "$jail_file" && ! -L "$jail_file" ]] || fail "Некорректный Fail2Ban файл: $jail_file"
    grep -qx '# Managed by 3x-ui-setup' "$jail_file" || fail "Fail2Ban файл $jail_file создан не этим проектом"
fi

jail_backup="$(mktemp)"
jail_staged="$(mktemp "${FAIL2BAN_JAIL_DIR:-/etc/fail2ban/jail.d}/.3x-ui-setup.XXXXXX")"
jail_existed=false
if [[ -f "$jail_file" ]]; then
    cp -p "$jail_file" "$jail_backup"
    jail_existed=true
fi
if ! (render_template "${PROJECT_DIR}/templates/fail2ban/3x-ui-setup.local.tpl" "$jail_staged"); then
    rm -f "$jail_staged" "$jail_backup"
    fail "Не удалось подготовить Fail2Ban jail"
fi
chmod 644 "$jail_staged"
mv -f "$jail_staged" "$jail_file"
if [[ "$legacy_migrated" == true ]]; then rm -f "$legacy_file"; fi

if fail2ban-client -t >> "$LOG_FILE" 2>&1 && systemctl enable fail2ban >> "$LOG_FILE" 2>&1 && systemctl restart fail2ban >> "$LOG_FILE" 2>&1; then
    jail_active=false
    for attempt in 1 2 3 4 5; do
        if systemctl is-active --quiet fail2ban && fail2ban-client ping >> "$LOG_FILE" 2>&1 &&
            fail2ban-client status sshd >> "$LOG_FILE" 2>&1 &&
            { ! bool_enabled "$ENABLE_NGINX_BOTSEARCH" || fail2ban-client status nginx-botsearch >> "$LOG_FILE" 2>&1; }; then
            jail_active=true
            break
        fi
        sleep 1
    done
    if [[ "$jail_active" == true ]]; then
        rm -f "$jail_backup" "$legacy_backup"
        summary_section "Fail2Ban"
        summary_add "Статус: включён"
        summary_add "Jail: sshd, nginx-botsearch=${ENABLE_NGINX_BOTSEARCH}"
        ok "Fail2Ban настроен"
        return 0
    fi
fi

if [[ "$jail_existed" == true ]]; then
    cp -p "$jail_backup" "$jail_file"
else
    rm -f "$jail_file"
fi
rm -f "$jail_backup"
if [[ "$legacy_migrated" == true ]]; then cp -p "$legacy_backup" "$legacy_file"; fi
rm -f "$legacy_backup"
systemctl restart fail2ban >> "$LOG_FILE" 2>&1 || warn "Fail2Ban требует ручной проверки после отката"
fail "Настройка Fail2Ban отклонена; прежний jail восстановлен"
