#!/usr/bin/env bash

set -Eeuo pipefail

REPO_URL="${REPO_URL:-https://github.com/Akxios/3x-ui-setup.git}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh}"
INSTALL_DIR="${INSTALL_DIR:-/opt/3x-ui-setup}"
COMMAND="${1:-${COMMAND:-menu}}"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-/tmp/vps-bootstrap-bootstrap.log}"

if [[ "$COMMAND" == "help" || "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    cat <<EOF
Использование:
  bash <(curl -fsSL ${BOOTSTRAP_URL})
  bash <(curl -fsSL ${BOOTSTRAP_URL}) install
  bash <(curl -fsSL ${BOOTSTRAP_URL}) remove
  bash <(curl -fsSL ${BOOTSTRAP_URL}) remove nginx
  bash <(curl -fsSL ${BOOTSTRAP_URL}) status
EOF
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
        echo "Запрашиваю root-доступ через sudo..."
        exec sudo bash -c "$(curl -fsSL "$BOOTSTRAP_URL")" -- "$@"
    fi

    echo "ОШИБКА: запустите от root"
    echo "Пример: sudo bash -c \"\$(curl -fsSL ${BOOTSTRAP_URL})\""
    exit 1
fi

run_bootstrap_cmd() {
    local description="$1"
    shift

    printf '==> %s\n' "$description"
    if "$@" >> "$BOOTSTRAP_LOG" 2>&1; then
        printf 'OK: %s\n' "$description"
    else
        echo "ОШИБКА: $description"
        tail -n 40 "$BOOTSTRAP_LOG" || true
        exit 1
    fi
}

prepare_repo() {
    : > "$BOOTSTRAP_LOG"

    run_bootstrap_cmd "Подготовка apt" apt-get update
    run_bootstrap_cmd "Установка базовых утилит" env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl nano ca-certificates

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        run_bootstrap_cmd "Обновление репозитория" git pull --ff-only
    else
        rm -rf "$INSTALL_DIR"
        run_bootstrap_cmd "Клонирование репозитория" git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi

    if [[ ! -f .env ]]; then
        cp .env.example .env
    fi
}

set_env_value() {
    local key="$1"
    local value="$2"
    local escaped="$value"

    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"

    if grep -q "^${key}=" .env; then
        sed -i "s|^${key}=.*|${key}=\"${escaped}\"|" .env
    else
        printf '%s="%s"\n' "$key" "$escaped" >> .env
    fi
}

configure_minimal_env() {
    # shellcheck disable=SC1091
    source .env

    echo
    echo "Минимальная настройка"
    echo

    local value

    read -r -p "Домен [${DOMAIN:-example.com}]: " value
    if [[ -n "$value" ]]; then
        set_env_value DOMAIN "$value"
        DOMAIN="$value"
    fi

    read -r -p "Email для Let's Encrypt [${LETSENCRYPT_EMAIL:-admin@example.com}]: " value
    if [[ -n "$value" ]]; then
        set_env_value LETSENCRYPT_EMAIL "$value"
    fi

    read -r -p "Xray TCP порт [${XRAY_TCP_PORTS:-8443}]: " value
    if [[ -n "$value" ]]; then
        set_env_value XRAY_TCP_PORTS "$value"
    fi

    read -r -p "Устанавливать 3x-ui? [Y/n] " value
    case "$value" in
        n|N|no|NO|No)
            set_env_value INSTALL_3X_UI "false"
            ;;
        *)
            set_env_value INSTALL_3X_UI "true"
            ;;
    esac
}

maybe_edit_env() {
    local value

    read -r -p "Открыть полный .env в редакторе? [y/N] " value
    if [[ "$value" =~ ^[Yy]$ ]]; then
        "${EDITOR:-nano}" .env
    fi
}

install_flow() {
    # shellcheck disable=SC1091
    source .env

    if [[ "${DOMAIN:-example.com}" == "example.com" ]]; then
        configure_minimal_env
    else
        echo
        echo "Текущий домен в .env: ${DOMAIN}"
        read -r -p "Использовать текущую конфигурацию? [Y/n] " reply
        if [[ "$reply" =~ ^[Nn]$ ]]; then
            configure_minimal_env
        fi
    fi

    maybe_edit_env

    echo
    read -r -p "Начать установку? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "Установка отменена."
        echo "Продолжить позже: sudo bash scripts/install.sh all"
        exit 0
    fi

    bash scripts/install.sh all
}

show_menu() {
    while true; do
        cat <<EOF

VPS Bootstrap
1) Установить / обновить сервер
2) Открыть .env
3) Удалить сервисы
4) Показать статус
0) Выход
EOF

        echo
        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                install_flow
                ;;
            2)
                "${EDITOR:-nano}" .env
                ;;
            3)
                bash scripts/install.sh remove
                ;;
            4)
                bash scripts/install.sh status
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Неизвестный пункт меню: $choice"
                ;;
        esac
    done
}

prepare_repo

case "$COMMAND" in
    menu|"")
        show_menu
        ;;
    install|all)
        install_flow
        ;;
    remove|delete|uninstall)
        bash scripts/install.sh remove "${@:2}"
        ;;
    status)
        bash scripts/install.sh status
        ;;
    *)
        echo "ОШИБКА: неизвестная команда: $COMMAND"
        exit 1
        ;;
esac
