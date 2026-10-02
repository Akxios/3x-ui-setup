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
  REMOVE_XUI_DATA=true       удалить /etc/x-ui
  REMOVE_UFW_DISABLE=true    отключить UFW, только если он был включён проектом
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

guard_remove_webroot() {
    validate_config_path WEB_ROOT
    [[ "$WEB_ROOT" == "/var/www/${DOMAIN}/html" ]] || fail "Автоудаление разрешено только для стандартного WEB_ROOT домена"
    local path entry entries
    for path in /var /var/www "/var/www/${DOMAIN}" "$WEB_ROOT"; do
        [[ ! -L "$path" ]] || fail "WEB_ROOT содержит символьную ссылку: $path"
    done
    [[ -d "$WEB_ROOT" ]] || return 0
    [[ -f "$WEB_ROOT/index.html" && ! -L "$WEB_ROOT/index.html" &&
        "$(sed -n '2p' "$WEB_ROOT/index.html")" == '<!-- Managed by 3x-ui-setup -->' ]] ||
        fail "WEB_ROOT не содержит страницу проекта; удаление запрещено"
    entries="$(mktemp)" || fail "Не удалось создать временный файл для проверки WEB_ROOT"
    if ! find "$WEB_ROOT" -mindepth 1 -print0 > "$entries"; then
        rm -f -- "$entries"
        fail "Не удалось проверить содержимое WEB_ROOT"
    fi
    while IFS= read -r -d '' entry; do
        case "$entry" in
            "$WEB_ROOT/index.html"|"$WEB_ROOT/.well-known"|"$WEB_ROOT/.well-known/acme-challenge") ;;
            *) rm -f -- "$entries"; fail "В WEB_ROOT есть пользовательские файлы: $entry; удаление запрещено" ;;
        esac
    done < "$entries"
    rm -f -- "$entries"
}

remove_nginx() {
    ensure_nginx_domain
    nginx_site_guard
    if bool_enabled "${REMOVE_WEB_ROOT:-false}"; then
        guard_remove_webroot
    fi
    confirm_remove "nginx-конфиг для ${DOMAIN}"

    local site_file="/etc/nginx/sites-available/${DOMAIN}"
    local enabled_file="/etc/nginx/sites-enabled/${DOMAIN}"

    local snapshot
    snapshot="$(mktemp)"
    local site_was_enabled=false
    if [[ -L "$enabled_file" ]]; then site_was_enabled=true; fi
    if [[ -f "$site_file" ]]; then cp -p "$site_file" "$snapshot"; fi
    backup_file "$site_file"
    rm -f "$enabled_file" "$site_file"

    if command_exists nginx && ! nginx -t >> "$LOG_FILE" 2>&1; then
        if [[ -s "$snapshot" ]]; then
            cp -p "$snapshot" "$site_file"
        fi
        if [[ "$site_was_enabled" == true ]]; then ln -sfn "$site_file" "$enabled_file"; fi
        rm -f "$snapshot"
        fail "После удаления сайта nginx -t завершился с ошибкой; прежний сайт восстановлен. Проверьте $LOG_FILE"
    fi
    if command_exists nginx && systemctl is-active --quiet nginx &&
        ! systemctl reload nginx >> "$LOG_FILE" 2>&1; then
        if [[ -s "$snapshot" ]]; then
            cp -p "$snapshot" "$site_file"
        fi
        if [[ "$site_was_enabled" == true ]]; then
            ln -sfn "$site_file" "$enabled_file"
            nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1 ||
                warn "После отката nginx требует ручной проверки"
        fi
        rm -f "$snapshot"
        fail "Nginx не перезагрузился после удаления сайта; прежний сайт восстановлен. Проверьте $LOG_FILE"
    fi
    rm -f "$snapshot"

    if bool_enabled "${REMOVE_WEB_ROOT:-false}"; then
        backup_file "$WEB_ROOT"
        rm -rf "$WEB_ROOT"
    else
        warn "WEB_ROOT оставлен на месте: ${WEB_ROOT}"
    fi

    if bool_enabled "${REMOVE_CERTBOT_CERT:-false}" && command_exists certbot; then
        certbot delete --cert-name "$DOMAIN" --non-interactive || true
    fi

    purge_packages_if_requested nginx certbot
    ok "nginx-конфиг удалён"
}

remove_fail2ban() {
    confirm_remove "Fail2Ban jail проекта"
    local jail_file="/etc/fail2ban/jail.d/3x-ui-setup.local"
    if [[ -f "$jail_file" ]]; then
        grep -qx '# Managed by 3x-ui-setup' "$jail_file" || fail "Jail не создан этим проектом: $jail_file"
        backup_file "$jail_file"
        local jail_snapshot
        jail_snapshot="$(mktemp)"
        cp -p "$jail_file" "$jail_snapshot"
        rm -f "$jail_file"
        if command_exists fail2ban-client; then
            if ! fail2ban-client -t; then
                cp -p "$jail_snapshot" "$jail_file"
                rm -f "$jail_snapshot"
                fail "Оставшаяся конфигурация Fail2Ban некорректна; jail проекта восстановлен"
            fi
            if ! systemctl restart fail2ban; then
                cp -p "$jail_snapshot" "$jail_file"
                systemctl restart fail2ban || warn "После отката Fail2Ban требует ручной проверки"
                rm -f "$jail_snapshot"
                fail "Fail2Ban не перезапустился; jail проекта восстановлен"
            fi
        fi
        rm -f "$jail_snapshot"
    fi
    ok "Fail2Ban jail проекта удалён"
}

remove_3x_ui() {
    confirm_remove "3x-ui / x-ui"

    systemctl stop x-ui >/dev/null 2>&1 || {
        systemctl is-active --quiet x-ui && fail "Не удалось остановить x-ui; файлы не удалялись"
    }
    if systemctl is-active --quiet x-ui || { command_exists pgrep && pgrep -x x-ui >/dev/null; }; then
        fail "Процесс x-ui всё ещё работает; файлы не удалялись"
    fi
    systemctl disable x-ui >/dev/null 2>&1 || warn "Не удалось отключить автозапуск x-ui"

    if [[ -d /etc/x-ui ]]; then
        backup_file /etc/x-ui
        if bool_enabled "${REMOVE_XUI_DATA:-false}"; then
            rm -rf /etc/x-ui
        else
            warn "Данные 3x-ui оставлены на месте: /etc/x-ui"
        fi
    fi
    if bool_enabled "${REMOVE_XUI_DATA:-false}"; then
        if [[ "$XUI_STATE_FILE" == /etc/3x-ui-setup/access.json &&
            "$XUI_ACCESS_FILE" == /root/3x-ui-access.txt ]]; then
            backup_file "$XUI_STATE_FILE"
            backup_file "$XUI_ACCESS_FILE"
            rm -f "$XUI_STATE_FILE" "${XUI_STATE_FILE}.pending" "$XUI_ACCESS_FILE" /etc/3x-ui-setup/settings-before.json
        else
            warn "Нестандартные файлы XUI_STATE_FILE/XUI_ACCESS_FILE сохранены; удалите их вручную после проверки"
        fi
    else
        if command_exists python3; then
            xui_setup invalidate
        else
            rm -f "$XUI_ACCESS_FILE"
            warn "Python3 не установлен; состояние access.json проверьте вручную"
        fi
    fi

    rm -f /etc/systemd/system/x-ui.service
    rm -f /usr/bin/x-ui
    rm -rf /usr/local/x-ui
    systemctl daemon-reload || true

    ok "3x-ui удалён"
}

remove_firewall() {
    if ! bool_enabled "${REMOVE_UFW_DISABLE:-false}"; then
        warn "UFW оставлен включённым. Для отключения UFW, ранее включённого проектом, задайте REMOVE_UFW_DISABLE=true"
        return 0
    fi
    [[ -f /etc/3x-ui-setup/ufw-enabled-by-project && ! -L /etc/3x-ui-setup/ufw-enabled-by-project ]] ||
        fail "UFW не был включён проектом; автоматическое отключение запрещено"
    confirm_remove "UFW"
    ufw --force disable || fail "Не удалось отключить UFW"
    rm -f /etc/3x-ui-setup/ufw-enabled-by-project
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
