#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

REPO_URL="${REPO_URL:-https://github.com/Akxios/3x-ui-setup.git}"
REPO_COMMIT="${REPO_COMMIT:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/3x-ui-setup}"
COMMAND="${1:-${COMMAND:-menu}}"
ASSUME_YES="${ASSUME_YES:-false}"
BOOTSTRAP_LOG="${BOOTSTRAP_LOG:-/var/log/3x-ui-setup-bootstrap.log}"

validate_install_dir() {
    case "$INSTALL_DIR" in
        ""|"/"|"/root"|"/home"|"/opt"|"/usr"|"/var"|"/tmp")
            echo "ОШИБКА: небезопасный INSTALL_DIR: ${INSTALL_DIR}"
            exit 1
            ;;
    esac
}

valid_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

if [[ "$COMMAND" == "help" || "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    cat <<EOF
Использование:
  sudo env REPO_COMMIT=<полный-SHA-коммита> bash bootstrap.sh [install|remove|status|access]

Скачивайте bootstrap.sh из того же commit SHA, что указан в REPO_COMMIT.

ASSUME_YES=true — установка без вопросов с уже заполненным .env.
EOF
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1 && [[ -r "$0" ]]; then
        tmp_script="$(mktemp)"
        echo "Запрашиваю root-доступ через sudo..."
        cp -- "$0" "$tmp_script"
        bootstrap_status=0
        sudo env \
            REPO_URL="$REPO_URL" \
            REPO_COMMIT="$REPO_COMMIT" \
            INSTALL_DIR="$INSTALL_DIR" \
            BOOTSTRAP_LOG="$BOOTSTRAP_LOG" \
            ASSUME_YES="$ASSUME_YES" \
            bash "$tmp_script" "$@" || bootstrap_status=$?
        rm -f -- "$tmp_script"
        exit "$bootstrap_status"
    fi

    echo "ОШИБКА: запустите от root"
    echo "Пример: sudo env REPO_COMMIT=<полный-SHA> bash bootstrap.sh install"
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
    [[ ! -L "$BOOTSTRAP_LOG" ]] || { echo "ОШИБКА: bootstrap-лог не должен быть symlink"; exit 1; }
    : > "$BOOTSTRAP_LOG"
    validate_install_dir
    [[ ! -L "$INSTALL_DIR" ]] || { echo "ОШИБКА: INSTALL_DIR не должен быть symlink"; exit 1; }
    if [[ -n "$REPO_COMMIT" && ! "$REPO_COMMIT" =~ ^[a-fA-F0-9]{40}$ ]]; then
        echo "ОШИБКА: REPO_COMMIT должен быть полным 40-символьным SHA коммита"
        exit 1
    fi

    run_bootstrap_cmd "Подготовка apt" apt-get update
    run_bootstrap_cmd "Установка базовых утилит" env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl nano ca-certificates python3

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        cd "$INSTALL_DIR"
        [[ "$(git remote get-url origin)" == "$REPO_URL" ]] || { echo "ОШИБКА: origin репозитория отличается от REPO_URL"; exit 1; }
        [[ -z "$(git status --porcelain)" ]] || { echo "ОШИБКА: в $INSTALL_DIR есть несохранённые изменения кода"; exit 1; }
        if [[ -n "$REPO_COMMIT" ]]; then
            run_bootstrap_cmd "Получение коммитов репозитория" git fetch origin
        else
            [[ -n "$(git symbolic-ref --quiet --short HEAD)" ]] || { echo "ОШИБКА: checkout закреплён за коммитом; задайте REPO_COMMIT или переключите ветку вручную"; exit 1; }
            run_bootstrap_cmd "Обновление репозитория" git pull --ff-only
        fi
    else
        [[ ! -e "$INSTALL_DIR" && ! -L "$INSTALL_DIR" ]] || { echo "ОШИБКА: $INSTALL_DIR уже существует и не является клоном проекта"; exit 1; }
        run_bootstrap_cmd "Клонирование репозитория" git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
    fi
    if [[ -n "$REPO_COMMIT" ]]; then
        if ! git cat-file -e "${REPO_COMMIT}^{commit}" 2>/dev/null; then
            run_bootstrap_cmd "Получение закреплённого коммита" git fetch origin "$REPO_COMMIT"
        fi
        git cat-file -e "${REPO_COMMIT}^{commit}" 2>/dev/null || { echo "ОШИБКА: коммит $REPO_COMMIT отсутствует в репозитории"; exit 1; }
        run_bootstrap_cmd "Закрепление версии проекта" git checkout --detach "$REPO_COMMIT"
        [[ "$(git rev-parse HEAD)" == "$REPO_COMMIT" ]] || { echo "ОШИБКА: checkout не совпадает с REPO_COMMIT"; exit 1; }
    fi

    if [[ ! -f .env ]]; then
        cp .env.example .env
    fi
    [[ ! -L .env ]] || { echo "ОШИБКА: .env не должен быть symlink"; exit 1; }
    chmod 600 .env
}

set_env_value() {
    local key="$1"
    local value="$2"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "ОШИБКА: некорректное имя настройки"; exit 1; }
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || { echo "ОШИБКА: переносы строк в .env не поддерживаются"; exit 1; }
    local quoted line replaced=false staged
    quoted="${value//\\/\\\\}"
    quoted="${quoted//\"/\\\"}"
    quoted="\"${quoted}\""
    staged="$(mktemp ./.env.XXXXXX)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$key="* ]]; then
            printf '%s=%s\n' "$key" "$quoted" >> "$staged"
            replaced=true
        else
            printf '%s\n' "$line" >> "$staged"
        fi
    done < .env
    if [[ "$replaced" == false ]]; then
        printf '%s=%s\n' "$key" "$quoted" >> "$staged"
    fi
    chmod 600 "$staged"
    mv -f "$staged" .env
}

configure_minimal_env() {
    load_env_file .env || exit 1

    echo
    echo "Минимальная настройка"
    echo

    local value

    while true; do
        read -r -p "Домен [${DOMAIN:-example.com}]: " value
        if [[ -n "$value" ]]; then
            DOMAIN="$value"
        fi

        if [[ "${DOMAIN:-example.com}" != "example.com" ]] && valid_domain "$DOMAIN"; then
            set_env_value DOMAIN "$DOMAIN"
            break
        fi

        echo "Укажите реальный домен, например example.org"
    done

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
    load_env_file .env || exit 1

    if [[ "${DOMAIN:-example.com}" == "example.com" ]]; then
        if [[ "$ASSUME_YES" == true ]]; then
            echo "ОШИБКА: сначала задайте DOMAIN и LETSENCRYPT_EMAIL в $INSTALL_DIR/.env"
            exit 1
        fi
        configure_minimal_env
    elif [[ "$ASSUME_YES" != true ]]; then
        echo
        echo "Текущий домен в .env: ${DOMAIN}"
        read -r -p "Использовать текущую конфигурацию? [Y/n] " reply
        if [[ "$reply" =~ ^[Nn]$ ]]; then
            configure_minimal_env
        fi
    fi

    if [[ "$ASSUME_YES" == true ]]; then
        bash scripts/install.sh all
        return
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
5) Показать данные доступа
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
            5)
                bash scripts/install.sh access
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

if [[ "$COMMAND" == access && -f "$INSTALL_DIR/scripts/install.sh" ]]; then
    exec bash "$INSTALL_DIR/scripts/install.sh" access
fi

prepare_repo
source "$INSTALL_DIR/scripts/lib/env-file.sh"

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
    access)
        bash scripts/install.sh access
        ;;
    status)
        bash scripts/install.sh status
        ;;
    *)
        echo "ОШИБКА: неизвестная команда: $COMMAND"
        exit 1
        ;;
esac
