#!/usr/bin/env bash

log() {
    echo -e "\n\033[1;34m==> $*\033[0m"
}

ok() {
    echo -e "\033[1;32mOK:\033[0m $*"
}

warn() {
    echo -e "\033[1;33mПРЕДУПРЕЖДЕНИЕ:\033[0m $*"
}

fail() {
    echo -e "\033[1;31mОШИБКА:\033[0m $*" >&2
    exit 1
}

bool_enabled() {
    case "${1:-false}" in
        true|yes|1|on)
            return 0
            ;;
        false|no|0|off|"")
            return 1
            ;;
        *)
            fail "Некорректное boolean-значение: $1"
            ;;
    esac
}

init_runtime_files() {
    local command="${1:-run}"
    local timestamp
    timestamp="$(date +%Y%m%d-%H%M%S)"

    LOG_DIR="${LOG_DIR:-/var/log/vps-bootstrap}"
    LOG_FILE="${LOG_FILE:-${LOG_DIR}/${command}-${timestamp}.log}"
    SUMMARY_FILE="${SUMMARY_FILE:-/root/vps-bootstrap-summary.txt}"

    mkdir -p "$LOG_DIR" "$(dirname "$SUMMARY_FILE")"
    : > "$LOG_FILE"
    : > "$SUMMARY_FILE"
    chmod 700 "$LOG_DIR"
    chmod 600 "$LOG_FILE" "$SUMMARY_FILE"

    export LOG_DIR LOG_FILE SUMMARY_FILE
}

append_log_header() {
    {
        echo ""
        echo "### $*"
        date
    } >> "${LOG_FILE:-/tmp/vps-bootstrap.log}"
}

run_logged() {
    local description="$1"
    shift

    log "$description"
    append_log_header "$description"

    if bool_enabled "${VERBOSE:-false}"; then
        "$@" 2>&1 | tee -a "${LOG_FILE:-/tmp/vps-bootstrap.log}"
    else
        if "$@" >> "${LOG_FILE:-/tmp/vps-bootstrap.log}" 2>&1; then
            ok "$description"
        else
            warn "Команда завершилась с ошибкой. Последние строки лога:"
            tail -n 40 "${LOG_FILE:-/tmp/vps-bootstrap.log}" || true
            fail "$description"
        fi
    fi
}

summary_add() {
    printf '%s\n' "$*" >> "${SUMMARY_FILE:-/root/vps-bootstrap-summary.txt}"
}

summary_section() {
    {
        echo ""
        echo "$*"
    } >> "${SUMMARY_FILE:-/root/vps-bootstrap-summary.txt}"
}

print_summary() {
    if [[ -f "${SUMMARY_FILE:-}" ]]; then
        echo
        echo -e "\033[1;32mИтоговая настройка:\033[0m"
        sed -n '1,220p' "$SUMMARY_FILE"
        echo
        echo "Лог установки: ${LOG_FILE:-не задан}"
        echo "Итог сохранён: ${SUMMARY_FILE:-не задан}"
    fi
}

backup_file() {
    local file="$1"
    local backup_dir="/root/vps-bootstrap-backups/$(date +%Y%m%d-%H%M%S)"

    if [[ -e "$file" ]]; then
        mkdir -p "$backup_dir"
        cp -a "$file" "$backup_dir/$(echo "$file" | sed 's#/#_#g')"
        ok "Создан бэкап: $file"
    fi
}

APT_UPDATED_FLAG="/var/run/vps-bootstrap-apt-updated"

apt_update_once() {
    if [[ ! -f "$APT_UPDATED_FLAG" ]]; then
        run_logged "Обновление списка пакетов" apt-get update
        touch "$APT_UPDATED_FLAG"
    fi
}

install_packages_if_missing() {
    local missing=()

    for package in "$@"; do
        if ! dpkg -s "$package" >/dev/null 2>&1; then
            missing+=("$package")
        fi
    done

    if [[ "${#missing[@]}" -gt 0 ]]; then
        apt_update_once
        run_logged "Установка пакетов: ${missing[*]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    else
        ok "Пакеты уже установлены: $*"
    fi
}
