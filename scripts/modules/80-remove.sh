#!/usr/bin/env bash

target="${1:-}"

usage_remove() {
    cat <<EOF
Использование:
  sudo bash scripts/install.sh remove
  sudo bash scripts/install.sh remove nginx
  sudo bash scripts/install.sh remove fail2ban
  sudo bash scripts/install.sh remove 3x-ui
  sudo bash scripts/install.sh remove ufw
  sudo bash scripts/install.sh remove all

Опционально через .env:
  REMOVE_WEB_ROOT=true       удалить ${WEB_ROOT}
  REMOVE_CERTBOT_CERT=true   удалить сертификат certbot для ${DOMAIN}
  REMOVE_FAIL2BAN_JAIL=true  удалить /etc/fail2ban/jail.local без marker-проверки
  REMOVE_XUI_DATA=true       удалить /etc/x-ui
  PURGE_PACKAGES=true        удалить apt-пакеты nginx/fail2ban/ufw
  REMOVE_CONFIRM=true        не спрашивать подтверждение
EOF
}

choose_target() {
    cat <<EOF
Что удалить?
  1) nginx-конфиг для домена
  2) Fail2Ban
  3) 3x-ui / x-ui
  4) UFW
  5) Всё управляемое этим скриптом
  0) Отмена
EOF

    echo
    read -r -p "Введите номер или несколько номеров через пробел/запятую: " choice

    if [[ -z "${choice//[[:space:],]/}" ]]; then
        fail "Не выбран компонент для удаления"
    fi

    case "${choice//,/ }" in
        *0*)
            fail "Удаление отменено"
            ;;
    esac

    for item in ${choice//,/ }; do
        case "$item" in
            1)
                remove_nginx
                ;;
            2)
                remove_fail2ban
                ;;
            3)
                remove_3x_ui
                ;;
            4)
                remove_firewall
                ;;
            5)
                remove_all
                return 0
                ;;
            *)
                fail "Неизвестный пункт меню: $item"
                ;;
        esac
    done
}

confirm_remove() {
    local name="$1"

    if bool_enabled "${REMOVE_CONFIRM:-false}"; then
        return 0
    fi

    echo
    warn "Будет удалён компонент: ${name}"
    read -r -p "Продолжить? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        fail "Удаление отменено"
    fi
}

ensure_nginx_domain() {
    if [[ -n "${DOMAIN:-}" && "$DOMAIN" != "example.com" ]]; then
        validate_domain "$DOMAIN"
        return 0
    fi

    echo
    read -r -p "Введите домен nginx-конфига для удаления: " DOMAIN
    validate_domain "$DOMAIN"

    if [[ -z "${WEB_ROOT:-}" || "$WEB_ROOT" == "/var/www/example.com/html" ]]; then
        WEB_ROOT="/var/www/${DOMAIN}/html"
    fi
}

purge_packages_if_requested() {
    if bool_enabled "${PURGE_PACKAGES:-false}"; then
        log "Удаление apt-пакетов: $*"
        DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"
        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    fi
}

remove_nginx() {
    ensure_nginx_domain
    confirm_remove "nginx-конфиг для ${DOMAIN}"

    local site_file="/etc/nginx/sites-available/${DOMAIN}"
    local enabled_file="/etc/nginx/sites-enabled/${DOMAIN}"

    backup_file "$site_file"
    rm -f "$enabled_file" "$site_file"

    if bool_enabled "${REMOVE_WEB_ROOT:-false}"; then
        backup_file "$WEB_ROOT"
        rm -rf "$WEB_ROOT"
    else
        warn "WEB_ROOT оставлен на месте: ${WEB_ROOT}"
    fi

    if bool_enabled "${REMOVE_CERTBOT_CERT:-false}" && command_exists certbot; then
        certbot delete --cert-name "$DOMAIN" --non-interactive || true
    fi

    if command_exists nginx; then
        nginx -t || true
        systemctl reload nginx || systemctl restart nginx || true
    fi

    purge_packages_if_requested nginx certbot
    ok "nginx-конфиг удалён"
}

remove_fail2ban() {
    confirm_remove "Fail2Ban"

    systemctl stop fail2ban >/dev/null 2>&1 || true
    systemctl disable fail2ban >/dev/null 2>&1 || true

    if [[ -f /etc/fail2ban/jail.local ]]; then
        if grep -q "Managed by vps-server" /etc/fail2ban/jail.local || bool_enabled "${REMOVE_FAIL2BAN_JAIL:-false}"; then
            backup_file /etc/fail2ban/jail.local
            rm -f /etc/fail2ban/jail.local
        else
            warn "/etc/fail2ban/jail.local не похож на файл этого скрипта, оставлен на месте"
        fi
    fi

    purge_packages_if_requested fail2ban
    ok "Fail2Ban остановлен/отключён"
}

remove_3x_ui() {
    confirm_remove "3x-ui / x-ui"

    systemctl stop x-ui >/dev/null 2>&1 || true
    systemctl disable x-ui >/dev/null 2>&1 || true

    if [[ -d /etc/x-ui ]]; then
        backup_file /etc/x-ui
        if bool_enabled "${REMOVE_XUI_DATA:-false}"; then
            rm -rf /etc/x-ui
        else
            warn "Данные 3x-ui оставлены на месте: /etc/x-ui"
        fi
    fi

    rm -f /etc/systemd/system/x-ui.service
    rm -f /usr/bin/x-ui
    rm -rf /usr/local/x-ui
    systemctl daemon-reload || true

    ok "3x-ui удалён"
}

remove_firewall() {
    confirm_remove "UFW"

    ufw --force disable || true
    purge_packages_if_requested ufw

    ok "UFW отключён"
}

remove_all() {
    confirm_remove "все управляемые сервисы"
    REMOVE_CONFIRM=true

    remove_3x_ui
    remove_fail2ban
    remove_nginx
    remove_firewall
}

case "$target" in
    nginx)
        remove_nginx
        ;;
    fail2ban)
        remove_fail2ban
        ;;
    3x-ui|x-ui)
        remove_3x_ui
        ;;
    firewall|ufw)
        remove_firewall
        ;;
    all)
        remove_all
        ;;
    help|-h|--help|"")
        usage_remove
        if [[ -z "$target" ]]; then
            choose_target
        fi
        ;;
    *)
        usage_remove
        fail "Неизвестный компонент для удаления: $target"
        ;;
esac
