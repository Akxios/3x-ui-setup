#!/usr/bin/env bash

# VPS Bootstrap — главный оркестратор
#
# Этот файл должен оставаться компактным.
# Основная логика находится в:
#   scripts/lib/*.sh
#   scripts/modules/*.sh

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"

source "${SCRIPT_DIR}/lib/common.sh"

on_error() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local command="${2:-unknown}"

    echo ""
    echo -e "\033[1;31mОШИБКА:\033[0m команда завершилась с кодом $exit_code"
    echo "Строка: $line_no"
    echo "Команда: $command"
    exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
source "${SCRIPT_DIR}/lib/checks.sh"
source "${SCRIPT_DIR}/lib/render-template.sh"
source "${SCRIPT_DIR}/lib/xui.sh"
source "${SCRIPT_DIR}/lib/nginx-site.sh"

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        fail ".env не найден. Сначала создайте его: cp .env.example .env"
    fi
    [[ ! -L "$ENV_FILE" ]] || fail ".env не должен быть символьной ссылкой"
    chmod 600 "$ENV_FILE"

    # shellcheck disable=SC1090
    source "$ENV_FILE"

    ok "Конфигурация загружена: $ENV_FILE"
}

set_default() {
    local name="$1"
    local value="$2"

    if [[ -z "${!name:-}" ]]; then
        printf -v "$name" '%s' "$value"
        export "$name"
    fi
}

apply_env_defaults() {
    require_env DOMAIN

    set_default ENABLE_WWW "false"

    set_default ENABLE_NGINX "true"
    set_default WEB_ROOT "/var/www/${DOMAIN}/html"
    set_default NGINX_AUTO_HTTPS "true"
    set_default NGINX_USE_HTTPS "false"
    set_default NGINX_CERT_PATH "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    set_default NGINX_CERT_KEY_PATH "/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

    set_default ENABLE_UFW "true"
    set_default UFW_DEFAULT_INCOMING "deny"
    set_default UFW_DEFAULT_OUTGOING "allow"
    set_default UFW_RESET_RULES "false"
    set_default CURRENT_SSH_PORTS ""
    set_default LIMIT_SSH_PORT "true"
    set_default WEB_TCP_PORTS "80 443"
    set_default WEB_UDP_PORTS ""

    set_default ENABLE_3X_UI_PORTS "true"
    set_default XRAY_TCP_PORTS "8443"
    set_default XRAY_UDP_PORTS ""
    set_default XUI_PANEL_TCP_PORTS ""
    set_default EXTRA_TCP_PORTS ""
    set_default EXTRA_UDP_PORTS ""

    set_default ENABLE_FAIL2BAN "true"
    set_default FAIL2BAN_BANTIME "1h"
    set_default FAIL2BAN_FINDTIME "10m"
    set_default FAIL2BAN_MAXRETRY "3"
    set_default FAIL2BAN_BANACTION "ufw"
    set_default FAIL2BAN_IGNORE_IPS "127.0.0.1/8 ::1"
    set_default ENABLE_NGINX_BOTSEARCH "true"

    set_default INSTALL_3X_UI "true"
    set_default THREE_X_UI_VERSION "v3.8.5"
    set_default THREE_X_UI_INSTALL_URL "https://raw.githubusercontent.com/MHSanaei/3x-ui/${THREE_X_UI_VERSION}/install.sh"
    set_default THREE_X_UI_INSTALL_SHA256 "4e3fe7fe00ef8e904ce6a0e9c36fd8a0c7179fe5e786f23e31801aee84c6347d"
    set_default XUI_INSTALL_VISIBLE "false"
    set_default XUI_AUTO_CONFIGURE "true"
    set_default XUI_STATE_FILE "/etc/3x-ui-setup/access.json"
    set_default XUI_ACCESS_FILE "/root/3x-ui-access.txt"
    set_default XUI_PANEL_PORT ""
    set_default XUI_SUB_PORT ""
    set_default XUI_USERNAME ""
    set_default XUI_PASSWORD ""
    set_default XUI_WEB_BASE_PATH ""

    set_default REMOVE_WEB_ROOT "false"
    set_default REMOVE_CERTBOT_CERT "false"
    set_default REMOVE_XUI_DATA "false"
    set_default PURGE_PACKAGES "false"
    set_default REMOVE_CONFIRM "false"

    set_default VERBOSE "false"
    set_default LOG_DIR "/var/log/vps-bootstrap"
}

validate_env() {
    local command="${1:-all}"

    require_env DOMAIN
    require_env WEB_ROOT

    if [[ "$command" != "remove" && "$command" != "delete" && "$command" != "uninstall" && "$command" != "status" ]]; then
        validate_domain "$DOMAIN"

        if [[ "$DOMAIN" == "example.com" ]]; then
            fail "Замените DOMAIN=example.com на реальный домен в .env"
        fi
    fi

    validate_bool ENABLE_NGINX
    validate_bool ENABLE_WWW
    validate_bool ENABLE_UFW
    validate_bool ENABLE_FAIL2BAN
    validate_bool INSTALL_3X_UI
    validate_bool XUI_INSTALL_VISIBLE
    validate_bool XUI_AUTO_CONFIGURE
    validate_bool NGINX_AUTO_HTTPS
    validate_bool NGINX_USE_HTTPS
    validate_bool ENABLE_3X_UI_PORTS

    validate_bool UFW_RESET_RULES
    validate_bool LIMIT_SSH_PORT
    validate_bool ENABLE_NGINX_BOTSEARCH
    validate_bool REMOVE_WEB_ROOT
    validate_bool REMOVE_CERTBOT_CERT
    validate_bool REMOVE_XUI_DATA
    validate_bool PURGE_PACKAGES
    validate_bool REMOVE_CONFIRM
    validate_bool VERBOSE

    if [[ "$command" == "all" || "$command" == "nginx" ]] &&
        bool_enabled "${ENABLE_NGINX:-true}" &&
        bool_enabled "${NGINX_AUTO_HTTPS:-true}"; then
        require_env LETSENCRYPT_EMAIL
    fi

    if [[ "$command" == "all" || "$command" == "3x-ui" || "$command" == "x-ui" ]] &&
        bool_enabled "${INSTALL_3X_UI:-false}"; then
        require_env THREE_X_UI_INSTALL_URL
        require_env THREE_X_UI_INSTALL_SHA256
        [[ "$THREE_X_UI_INSTALL_SHA256" =~ ^[a-fA-F0-9]{64}$ ]] || fail "THREE_X_UI_INSTALL_SHA256 должен быть SHA-256 (64 hex-символа)"
    fi
}

run_module() {
    local module_path="$1"
    shift

    if [[ ! -f "$module_path" ]]; then
        fail "Модуль не найден: $module_path"
    fi

    log "Запуск модуля: ${module_path#$PROJECT_DIR/}"

    # shellcheck disable=SC1090
    source "$module_path" "$@"
}

usage() {
    cat <<EOF
Использование:
  sudo bash scripts/install.sh all
  sudo bash scripts/install.sh packages
  sudo bash scripts/install.sh nginx
  sudo bash scripts/install.sh firewall
  sudo bash scripts/install.sh fail2ban
  sudo bash scripts/install.sh 3x-ui
  sudo bash scripts/install.sh status
  sudo bash scripts/install.sh access
  sudo bash scripts/install.sh remove
  sudo bash scripts/install.sh remove nginx|fail2ban|3x-ui|ufw|all

Перед первым запуском:
  cp .env.example .env
  nano .env
EOF
}

main() {
    local command="${1:-all}"

    case "$command" in
        help|-h|--help)
            usage
            exit 0
            ;;
    esac

    require_root
    if [[ "$command" == "access" ]]; then
        if [[ -f "$ENV_FILE" ]]; then
            [[ ! -L "$ENV_FILE" ]] || fail ".env не должен быть символьной ссылкой"
            chmod 600 "$ENV_FILE"
            source "$ENV_FILE"
        fi
        XUI_STATE_FILE="${XUI_STATE_FILE:-/etc/3x-ui-setup/access.json}"
        XUI_ACCESS_FILE="${XUI_ACCESS_FILE:-/root/3x-ui-access.txt}"
        show_xui_access
        return 0
    fi
    require_apt_system
    load_env
    apply_env_defaults
    validate_env "$command"
    init_runtime_files "$command"
    summary_add "Домен: ${DOMAIN}"
    summary_add "Лог: ${LOG_FILE}"

    case "$command" in
        all)
            prepare_xui
            run_module "${SCRIPT_DIR}/modules/00-packages.sh"
            run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            run_module "${SCRIPT_DIR}/modules/20-nginx.sh"
            run_module "${SCRIPT_DIR}/modules/40-fail2ban.sh"

            if bool_enabled "${INSTALL_3X_UI:-false}"; then
                run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
                run_module "${SCRIPT_DIR}/modules/60-configure-xui.sh"
            fi

            run_module "${SCRIPT_DIR}/modules/90-status.sh"
            print_summary
            if bool_enabled "$INSTALL_3X_UI" && bool_enabled "$XUI_AUTO_CONFIGURE"; then
                show_xui_access
            fi
            ;;
        packages)
            run_module "${SCRIPT_DIR}/modules/00-packages.sh"
            ;;
        nginx)
            run_module "${SCRIPT_DIR}/modules/20-nginx.sh"
            ;;
        firewall|ufw)
            run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            ;;
        fail2ban)
            run_module "${SCRIPT_DIR}/modules/40-fail2ban.sh"
            ;;
        3x-ui|x-ui)
            prepare_xui
            if bool_enabled "$INSTALL_3X_UI" && bool_enabled "$XUI_AUTO_CONFIGURE"; then
                run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            fi
            run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
            run_module "${SCRIPT_DIR}/modules/60-configure-xui.sh"
            if bool_enabled "$INSTALL_3X_UI" && bool_enabled "$XUI_AUTO_CONFIGURE"; then
                show_xui_access
            fi
            ;;
        status)
            run_module "${SCRIPT_DIR}/modules/90-status.sh"
            ;;
        remove|delete|uninstall)
            run_module "${SCRIPT_DIR}/modules/80-remove.sh" "${@:2}"
            ;;
        *)
            usage
            fail "Неизвестная команда: $command"
            ;;
    esac
}

main "$@"
