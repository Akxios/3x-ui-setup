#!/usr/bin/env bash

# VPS Bootstrap — главный оркестратор
#
# Этот файл должен оставаться компактным.
# Основная логика находится в:
#   scripts/lib/*.sh
#   scripts/modules/*.sh

set -Eeuo pipefail

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

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        fail ".env не найден. Сначала создайте его: cp .env.example .env"
    fi

    # shellcheck disable=SC1090
    source "$ENV_FILE"

    ok "Конфигурация загружена: $ENV_FILE"
}

validate_env() {
    require_env DOMAIN
    require_env WEB_ROOT

    validate_domain "$DOMAIN"

    validate_bool ENABLE_NGINX
    validate_bool ENABLE_WWW
    validate_bool ENABLE_UFW
    validate_bool ENABLE_FAIL2BAN
    validate_bool INSTALL_3X_UI
    validate_bool NGINX_AUTO_HTTPS
    validate_bool NGINX_USE_HTTPS
    validate_bool ENABLE_3X_UI_PORTS

    if [[ "${NGINX_AUTO_HTTPS:-false}" == "true" ]]; then
        require_env LETSENCRYPT_EMAIL
    fi

    if [[ "${INSTALL_3X_UI:-false}" == "true" ]]; then
        require_env THREE_X_UI_INSTALL_URL
    fi
}

run_module() {
    local module_path="$1"

    if [[ ! -f "$module_path" ]]; then
        fail "Модуль не найден: $module_path"
    fi

    log "Запуск модуля: ${module_path#$PROJECT_DIR/}"

    # shellcheck disable=SC1090
    source "$module_path"
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

Перед первым запуском:
  cp .env.example .env
  nano .env
EOF
}

main() {
    local command="${1:-all}"

    require_root
    require_apt_system
    load_env
    validate_env

    case "$command" in
        all)
            run_module "${SCRIPT_DIR}/modules/00-packages.sh"
            run_module "${SCRIPT_DIR}/modules/30-firewall.sh"
            run_module "${SCRIPT_DIR}/modules/20-nginx.sh"
            run_module "${SCRIPT_DIR}/modules/40-fail2ban.sh"

            if [[ "${INSTALL_3X_UI:-false}" == "true" ]]; then
                run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
            fi

            run_module "${SCRIPT_DIR}/modules/90-status.sh"
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
            run_module "${SCRIPT_DIR}/modules/50-3x-ui.sh"
            ;;
        status)
            run_module "${SCRIPT_DIR}/modules/90-status.sh"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            usage
            fail "Неизвестная команда: $command"
            ;;
    esac
}

main "$@"
