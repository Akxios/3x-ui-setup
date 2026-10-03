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

validate_bootstrap_log() {
    case "$BOOTSTRAP_LOG" in
        /var/log/3x-ui-setup-bootstrap.log) ;;
        /var/log/vps-bootstrap/*.log)
            [[ "$BOOTSTRAP_LOG" =~ ^/var/log/vps-bootstrap/[A-Za-z0-9._-]+\.log$ ]] || {
                echo "ОШИБКА: небезопасный BOOTSTRAP_LOG" >&2
                exit 1
            }
            ;;
        *) echo "ОШИБКА: BOOTSTRAP_LOG должен находиться в /var/log/vps-bootstrap" >&2; exit 1 ;;
    esac
    [[ ! -L /var/log && ! -L /var/log/vps-bootstrap && ! -L "$BOOTSTRAP_LOG" ]] || {
        echo "ОШИБКА: символьная ссылка в пути BOOTSTRAP_LOG" >&2
        exit 1
    }
    if [[ -d /var/log/vps-bootstrap && "$(stat -c %u /var/log/vps-bootstrap)" != 0 ]]; then
        echo "ОШИБКА: каталог bootstrap-лога должен принадлежать root" >&2
        exit 1
    fi
}

valid_domain() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]
}

if [[ "$COMMAND" == "help" || "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    cat <<EOF
Использование:
  sudo bash bootstrap.sh [install|preflight|doctor|upgrade-3x-ui|remove|status|access]
  sudo env REPO_COMMIT=<полный-SHA-коммита> bash bootstrap.sh [install|preflight|doctor|upgrade-3x-ui|remove|status|access]

REPO_COMMIT необязателен. Для закреплённой установки скачайте bootstrap.sh
из того же коммита, что указан в REPO_COMMIT.

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
    echo "Пример: sudo bash bootstrap.sh install"
    exit 1
fi

case "$COMMAND" in
    status|access|remove|delete|uninstall|preflight|doctor|upgrade-3x-ui)
        validate_install_dir
        [[ ! -L "$INSTALL_DIR" && -f "$INSTALL_DIR/scripts/install.sh" &&
            ! -L "$INSTALL_DIR/scripts/install.sh" ]] || {
            echo "ОШИБКА: проект не установлен в $INSTALL_DIR" >&2
            exit 1
        }
        exec bash "$INSTALL_DIR/scripts/install.sh" "$COMMAND" "${@:2}"
        ;;
esac

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
    validate_bootstrap_log
    if [[ "$BOOTSTRAP_LOG" == /var/log/vps-bootstrap/* ]]; then
        install -d -m 700 /var/log/vps-bootstrap
    fi
    : > "$BOOTSTRAP_LOG"
    chmod 600 "$BOOTSTRAP_LOG"
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
    staged="$(mktemp ./.env.XXXXXX)" || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
            if [[ "$replaced" == true ]]; then
                rm -f -- "$staged"
                echo "ОШИБКА: настройка $key встречается в .env более одного раза" >&2
                return 1
            fi
            printf '%s=%s\n' "$key" "$quoted" >> "$staged"
            replaced=true
        else
            printf '%s\n' "$line" >> "$staged"
        fi
    done < .env
    if [[ "$replaced" == false ]]; then
        printf '%s=%s\n' "$key" "$quoted" >> "$staged"
    fi
    chmod 600 "$staged" || { rm -f -- "$staged"; return 1; }
    mv -f "$staged" .env || { rm -f -- "$staged"; return 1; }
}

configure_minimal_env() {
    load_env_file .env || return 1

    echo
    echo "Минимальная настройка"
    echo

    local value

    while true; do
        read -r -p "Домен [${DOMAIN:-example.com}]: " value || return 1
        if [[ -n "$value" ]]; then
            DOMAIN="$value"
        fi

        if [[ "${DOMAIN:-example.com}" != "example.com" ]] && valid_domain "$DOMAIN"; then
            set_env_value DOMAIN "$DOMAIN" || return 1
            break
        fi

        echo "Укажите реальный домен, например example.org"
    done

    read -r -p "Email для Let's Encrypt [${LETSENCRYPT_EMAIL:-admin@example.com}]: " value || return 1
    if [[ -n "$value" ]]; then
        set_env_value LETSENCRYPT_EMAIL "$value" || return 1
    fi

    read -r -p "Xray TCP порт [${XRAY_TCP_PORTS:-8443}]: " value || return 1
    if [[ -n "$value" ]]; then
        set_env_value XRAY_TCP_PORTS "$value" || return 1
    fi

    read -r -p "Устанавливать 3x-ui? [Y/n] " value || return 1
    case "$value" in
        n|N|no|NO|No)
            set_env_value INSTALL_3X_UI "false" || return 1
            ;;
        *)
            set_env_value INSTALL_3X_UI "true" || return 1
            ;;
    esac
}

maybe_edit_env() {
    local value

    read -r -p "Открыть полный .env в редакторе? [y/N] " value || return 1
    if [[ "$value" =~ ^[Yy]$ ]]; then
        "${EDITOR:-nano}" .env || return 1
    fi
}

choose_site_template() {
    load_env_file .env || return 1
    local current="${SITE_TEMPLATE:-tribe}" answer selected
    case "$current" in
        tribe|numbers|notepad) ;;
        *) current="не выбран" ;;
    esac
    cat <<'EOF'

╭─ Выбор шаблона сайта ─────────────────────────────────────────────────╮
│  1  Племя                                                           │
│     Небольшая игра: люди, еда, сезоны. Прогресс — в браузере.        │
│                                                                      │
│  2  Генератор чисел                                                  │
│     Диапазон, серия чисел и история. История — в браузере.           │
│                                                                      │
│  3  Блокнот                                                          │
│     Заметка с автосохранением и экспортом .txt. Текст — в браузере.  │
╰──────────────────────────────────────────────────────────────────────╯
EOF
    printf 'Текущий выбор: %s\n' "$current"
    read -r -p "Выберите 1–3 [Enter — оставить текущий]: " answer || return 1
    case "$answer" in
        "")
            [[ "$current" != "не выбран" ]] || { echo "ОШИБКА: выберите шаблон 1–3" >&2; return 1; }
            return 0
            ;;
        1) selected=tribe ;;
        2) selected=numbers ;;
        3) selected=notepad ;;
        *) echo "ОШИБКА: выберите 1, 2 или 3" >&2; return 1 ;;
    esac
    set_env_value SITE_TEMPLATE "$selected"
}

install_flow() {
    load_env_file .env || return 1

    if [[ "${DOMAIN:-example.com}" == "example.com" ]]; then
        if [[ "$ASSUME_YES" == true ]]; then
            echo "ОШИБКА: сначала задайте DOMAIN и LETSENCRYPT_EMAIL в $INSTALL_DIR/.env"
            return 1
        fi
        configure_minimal_env || return 1
    elif [[ "$ASSUME_YES" != true ]]; then
        echo
        echo "Текущий домен в .env: ${DOMAIN}"
        read -r -p "Использовать текущую конфигурацию? [Y/n] " reply || return 1
        if [[ "$reply" =~ ^[Nn]$ ]]; then
            configure_minimal_env || return 1
        fi
    fi

    if [[ "$ASSUME_YES" == true ]]; then
        bash scripts/install.sh all
        return $?
    fi
    maybe_edit_env || return 1
    choose_site_template || return 1

    echo
    read -r -p "Начать установку? [y/N] " reply || return 1
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        echo "Установка отменена."
        echo "Продолжить позже: sudo bash scripts/install.sh all"
        return 0
    fi

    bash scripts/install.sh all
}

menu_service_status() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        printf 'работает'
    else
        printf 'не работает'
    fi
}

menu_firewall_status() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        printf 'включён'
    else
        printf 'не включён'
    fi
}

menu_header() {
    if ! load_env_file .env; then
        echo "ПРЕДУПРЕЖДЕНИЕ: .env содержит ошибку; исправьте файл через пункт настройки" >&2
    fi
    local domain="${DOMAIN:-не задан}" cert="${NGINX_CERT_PATH:-/etc/letsencrypt/live/${DOMAIN:-example.com}/fullchain.pem}"
    local tls_status="нет сертификата"
    if [[ -f "$cert" ]] && command -v openssl >/dev/null 2>&1 &&
        openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
        tls_status="действует"
    fi
    printf '\n╭─ 3x-ui setup ──────────────────────────────────╮\n'
    printf '│ Домен: %-40.40s │\n' "$domain"
    printf '│ Панель: %-12s HTTPS: %-16s │\n' "$(menu_service_status x-ui)" "$tls_status"
    printf '│ Nginx: %-13s UFW: %-18s │\n' "$(menu_service_status nginx)" "$(menu_firewall_status)"
    printf '│ Fail2Ban: %-36s │\n' "$(menu_service_status fail2ban)"
    printf '╰─────────────────────────────────────────────────╯\n'
}

menu_settings() {
    printf '\n1) Быстрая настройка\n2) Открыть полный .env\n3) Выбрать шаблон сайта\n0) Назад\n'
    local answer
    read -r -p "Выберите действие: " answer || return 1
    case "$answer" in
        1) configure_minimal_env ;;
        2) "${EDITOR:-nano}" .env ;;
        3) choose_site_template ;;
        0) return 0 ;;
        *) echo "Неизвестный пункт: $answer"; return 1 ;;
    esac
}

menu_last_log() {
    local newest="" candidate
    local log_dir="${LOG_DIR:-/var/log/vps-bootstrap}"
    if [[ -d "$log_dir" ]]; then
        while IFS= read -r candidate; do
            newest="$candidate"
            break
        done < <(find "$log_dir" -maxdepth 1 -type f -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr)
    fi
    if [[ -n "$newest" ]]; then
        printf 'Последний лог: %s\n' "${newest#* }"
    else
        echo "Логов установки пока нет"
    fi
}

menu_backups() {
    printf '\nРезервные копии проекта:\n'
    if [[ -d /root/vps-bootstrap-backups ]]; then
        find /root/vps-bootstrap-backups -mindepth 1 -maxdepth 1 -type d -print | sort -r | sed -n '1,10p'
    else
        echo "Копий пока нет"
    fi
    echo "Перед восстановлением проверьте состав копии и остановите соответствующий сервис."
}

show_menu() {
    while true; do
        menu_header
        cat <<EOF
1) Установить / применить настройки
2) Настроить домен, порты и защиту
3) Показать адреса и реквизиты
4) Проверить конфигурацию
5) Найти последний лог
6) Обновить версию 3x-ui
7) Резервные копии
8) Удалить компоненты
9) Диагностика установленного сервера
0) Выход
EOF

        echo
        read -r -p "Выберите действие: " choice

        case "$choice" in
            1)
                if ! install_flow; then echo "Установка завершилась с ошибкой; вы вернулись в меню"; fi
                ;;
            2)
                if ! menu_settings; then echo "Настройка не завершена"; fi
                ;;
            3)
                if ! bash scripts/install.sh access; then echo "Данные доступа пока недоступны"; fi
                ;;
            4)
                if ! bash scripts/install.sh preflight; then echo "Проверка нашла ошибку"; fi
                ;;
            5)
                menu_last_log
                ;;
            6)
                if ! bash scripts/install.sh upgrade-3x-ui; then echo "Обновление 3x-ui не завершено"; fi
                ;;
            7)
                menu_backups
                ;;
            8)
                if ! bash scripts/install.sh remove; then echo "Удаление не завершено"; fi
                ;;
            9)
                if ! bash scripts/install.sh doctor; then echo "Диагностика обнаружила проблемы"; fi
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
