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
    if [[ -z "${SUMMARY_FILE:-}" || ( "$command" != "all" && "${SUMMARY_FILE:-}" == "/root/vps-bootstrap-summary.txt" ) ]]; then
        if [[ "$command" == "all" ]]; then
            SUMMARY_FILE="/root/vps-bootstrap-summary.txt"
        else
            SUMMARY_FILE="${LOG_DIR}/${command}-${timestamp}-summary.txt"
        fi
    fi

    validate_runtime_paths
    mkdir -p "$LOG_DIR" "$(dirname "$SUMMARY_FILE")"
    chmod 700 "$LOG_DIR"
    : > "$LOG_FILE"
    : > "$SUMMARY_FILE"
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
        if "$@" 2>&1 | tee -a "${LOG_FILE:-/tmp/vps-bootstrap.log}"; then
            ok "$description"
        else
            fail "$description"
        fi
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
    local backup_root="/root/vps-bootstrap-backups"
    local backup_dir="${backup_root}/$(date +%Y%m%d-%H%M%S)"

    if [[ -e "$file" ]]; then
        [[ ! -L "$backup_root" && ( ! -e "$backup_root" || -d "$backup_root" ) ]] ||
            fail "Каталог резервных копий не должен быть символьной ссылкой"
        if [[ -d "$backup_root" ]]; then
            [[ "$(stat -c %u "$backup_root")" == 0 ]] || fail "Каталог резервных копий должен принадлежать root"
        fi
        install -d -m 700 "$backup_root"
        [[ ! -L "$backup_dir" ]] || fail "Каталог резервной копии не должен быть символьной ссылкой"
        install -d -m 700 "$backup_dir"
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
        record_project_packages "${missing[@]}"
    else
        ok "Пакеты уже установлены: $*"
    fi
}

record_project_packages() {
    local marker_dir="/etc/3x-ui-setup"
    local marker_file="$marker_dir/apt-installed-by-project"
    local staged package
    [[ ! -L "$marker_dir" && ( ! -e "$marker_dir" || -d "$marker_dir" ) ]] ||
        fail "Каталог учёта пакетов не должен быть символьной ссылкой"
    if [[ -d "$marker_dir" ]]; then
        [[ "$(stat -c %u "$marker_dir")" == 0 ]] || fail "Каталог учёта пакетов должен принадлежать root"
    fi
    [[ ! -L "$marker_file" && ( ! -e "$marker_file" || -f "$marker_file" ) ]] ||
        fail "Файл учёта пакетов не должен быть символьной ссылкой"
    if [[ -f "$marker_file" ]]; then
        [[ "$(stat -c %u "$marker_file")" == 0 ]] || fail "Файл учёта пакетов должен принадлежать root"
    fi
    for package in "$@"; do
        [[ "$package" =~ ^[a-z0-9][a-z0-9.+-]*$ ]] || fail "Некорректное имя пакета: $package"
    done
    install -d -m 700 "$marker_dir"
    staged="$(mktemp "$marker_dir/.apt-installed.XXXXXX")"
    if [[ -f "$marker_file" ]]; then cat "$marker_file" > "$staged"; fi
    for package in "$@"; do
        printf '%s\n' "$package" >> "$staged"
    done
    sort -u "$staged" -o "$staged"
    chmod 600 "$staged"
    mv -f "$staged" "$marker_file"
}
