#!/usr/bin/env bash

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fail "Запустите от root: sudo bash scripts/install.sh all"
    fi
}

require_apt_system() {
    if ! command -v apt-get >/dev/null 2>&1; then
        fail "Скрипт поддерживает только Debian/Ubuntu-подобные системы с apt-get."
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_ssh_ports() {
    if [[ -n "${CURRENT_SSH_PORTS:-}" ]]; then
        echo "$CURRENT_SSH_PORTS"
        return 0
    fi

    local ports=""
    # The active SSH session is authoritative even when sshd runs through
    # systemd socket activation or a Match block changes sshd -T output.
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        local remote_ip remote_port local_ip local_port
        read -r remote_ip remote_port local_ip local_port <<< "$SSH_CONNECTION"
        if [[ "$local_port" =~ ^[0-9]+$ ]]; then
            ports="$ports $local_port"
        fi
    fi

    if command_exists systemctl; then
        local sockets
        sockets="$(systemctl show ssh.socket sshd.socket -p Listen --value 2>/dev/null || true)"
        ports="$ports $(printf '%s\n' "$sockets" | sed -nE 's/.*:([0-9]+) \(Stream\).*/\1/p' | tr '\n' ' ')"
    fi

    if command_exists ss; then
        ports="$ports $(ss -H -ltnp 2>/dev/null | awk '/users:\(\("sshd"/ {port=$4; sub(/^.*:/, "", port); print port}' | tr '\n' ' ')"
    fi

    if [[ -z "${ports// }" ]] && command_exists sshd; then
        ports="$ports $(sshd -T 2>/dev/null | awk '/^port / {print $2}' | tr '\n' ' ')"
    fi

    ports="$(printf '%s\n' $ports | awk '/^[0-9]+$/ && $1 >= 1 && $1 <= 65535' | sort -nu | tr '\n' ' ')"
    if [[ -z "${ports// }" ]]; then
        fail "Не удалось определить SSH-порт. Укажите CURRENT_SSH_PORTS в .env перед включением UFW"
    fi
    echo "$ports"
}

require_env() {
    local name="$1"

    if [[ -z "${!name:-}" ]]; then
        fail "Обязательная переменная не задана: $name"
    fi
}

validate_bool() {
    local name="$1"
    local value="${!name:-}"

    case "$value" in
        true|false|yes|no|1|0|on|off|"")
            ;;
        *)
            fail "Переменная $name должна быть boolean, сейчас: $value"
            ;;
    esac
}

validate_domain() {
    local domain="$1"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]]; then
        fail "Некорректный DOMAIN: $domain"
    fi
}

validate_config_path() {
    local name="$1" path="${!1:-}"
    [[ "$path" == /* && "$path" != / && "$path" =~ ^/[A-Za-z0-9._/-]+$ &&
        "$path" != *//* && "$path" != */ ]] || fail "$name: требуется абсолютный путь без пробелов и спецсимволов"
    local component
    local -a components
    IFS=/ read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        [[ "$component" != . && "$component" != .. ]] || fail "$name: компоненты . и .. запрещены"
    done
}

validate_no_symlink_components() {
    local target="$1" current="" component
    local -a components
    IFS=/ read -r -a components <<< "$target"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        current="${current}/${component}"
        [[ ! -L "$current" ]] || fail "Символьная ссылка в пути: $current"
    done
}

validate_runtime_paths() {
    [[ "$LOG_DIR" == /var/log/vps-bootstrap || "$LOG_DIR" == /var/log/vps-bootstrap/* ]] ||
        fail "LOG_DIR должен находиться внутри /var/log/vps-bootstrap"
    validate_config_path LOG_DIR
    validate_no_symlink_components "$LOG_DIR"
    [[ ! -e "$LOG_DIR" || -d "$LOG_DIR" ]] || fail "LOG_DIR уже существует и не является каталогом"
    if [[ -d "$LOG_DIR" ]]; then
        [[ "$(stat -c %u "$LOG_DIR")" == 0 ]] || fail "LOG_DIR должен принадлежать root"
    fi

    [[ "$LOG_FILE" == "$LOG_DIR/"*.log ]] || fail "LOG_FILE должен быть .log-файлом внутри LOG_DIR"
    validate_config_path LOG_FILE
    validate_no_symlink_components "$LOG_FILE"
    [[ ! -e "$LOG_FILE" || -f "$LOG_FILE" ]] || fail "LOG_FILE уже существует и не является файлом"

    [[ "$SUMMARY_FILE" == /root/vps-bootstrap-summary.txt ||
        "$SUMMARY_FILE" == "$LOG_DIR/"*.txt ]] ||
        fail "SUMMARY_FILE должен быть /root/vps-bootstrap-summary.txt или .txt-файлом внутри LOG_DIR"
    validate_config_path SUMMARY_FILE
    validate_no_symlink_components "$SUMMARY_FILE"
    [[ ! -e "$SUMMARY_FILE" || -f "$SUMMARY_FILE" ]] || fail "SUMMARY_FILE уже существует и не является файлом"
}

validate_port_list() {
    local name="$1" number
    local -a numbers
    read -r -a numbers <<< "${!name:-}"
    for number in "${numbers[@]}"; do
        [[ "$number" =~ ^[0-9]+$ ]] && (( 10#$number >= 1 && 10#$number <= 65535 )) ||
            fail "$name содержит некорректный порт: $number"
    done
}

validate_install_settings() {
    local name
    local -a ignored_ips
    case "$UFW_DEFAULT_INCOMING" in deny|reject|allow) ;; *) fail "UFW_DEFAULT_INCOMING: ожидается deny, reject или allow" ;; esac
    case "$UFW_DEFAULT_OUTGOING" in deny|reject|allow) ;; *) fail "UFW_DEFAULT_OUTGOING: ожидается deny, reject или allow" ;; esac
    for name in CURRENT_SSH_PORTS WEB_TCP_PORTS WEB_UDP_PORTS XRAY_TCP_PORTS XRAY_UDP_PORTS XUI_PANEL_TCP_PORTS EXTRA_TCP_PORTS EXTRA_UDP_PORTS; do
        validate_port_list "$name"
    done
    for name in XUI_PANEL_PORT XUI_SUB_PORT; do
        if [[ -n "${!name:-}" ]]; then
            [[ "${!name}" =~ ^[0-9]+$ ]] || fail "$name должен содержать один TCP-порт"
            validate_port_list "$name"
        fi
    done
    if [[ -n "${XUI_PANEL_PORT:-}" && -n "${XUI_SUB_PORT:-}" ]]; then
        [[ "$XUI_PANEL_PORT" != "$XUI_SUB_PORT" ]] || fail "Порты панели и подписок должны различаться"
    fi
    if [[ -n "${LETSENCRYPT_EMAIL:-}" ]]; then
        [[ "$LETSENCRYPT_EMAIL" =~ ^[^[:space:]@]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] ||
            fail "LETSENCRYPT_EMAIL: некорректный email"
    fi
    if bool_enabled "${ENABLE_FAIL2BAN:-true}"; then
        for name in FAIL2BAN_BANTIME FAIL2BAN_FINDTIME; do
            [[ "${!name:-}" =~ ^[1-9][0-9]*[smhdw]$ ]] || fail "$name: ожидается длительность, например 10m или 1h"
        done
        [[ "$FAIL2BAN_MAXRETRY" =~ ^[0-9]+$ ]] &&
            (( 10#$FAIL2BAN_MAXRETRY >= 1 && 10#$FAIL2BAN_MAXRETRY <= 100 )) ||
            fail "FAIL2BAN_MAXRETRY должен быть числом от 1 до 100"
        [[ "$FAIL2BAN_BANACTION" =~ ^[A-Za-z0-9_-]+$ ]] || fail "FAIL2BAN_BANACTION содержит недопустимые символы"
        read -r -a ignored_ips <<< "$FAIL2BAN_IGNORE_IPS"
        python3 -c 'import ipaddress,sys; [ipaddress.ip_network(item, strict=False) for item in sys.argv[1:]]' "${ignored_ips[@]}" 2>/dev/null ||
            fail "FAIL2BAN_IGNORE_IPS должен содержать IP-адреса или CIDR"
    fi
    [[ "$THREE_X_UI_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        fail "THREE_X_UI_VERSION должен быть закреплённым тегом вида v3.8.5"
    [[ "$THREE_X_UI_INSTALL_URL" == https://* ]] || fail "THREE_X_UI_INSTALL_URL должен использовать HTTPS"
    if [[ "$THREE_X_UI_VERSION" != v3.8.5 &&
        "${THREE_X_UI_INSTALL_SHA256,,}" == 4e3fe7fe00ef8e904ce6a0e9c36fd8a0c7179fe5e786f23e31801aee84c6347d ]]; then
        fail "При смене THREE_X_UI_VERSION задайте SHA-256 installer выбранной версии"
    fi
}

check_port_free() {
    local port="$1"
    local proto="${2:-tcp}"

    if command_exists ss; then
        if ss -tuln | grep -qE ":${port}\b"; then
            warn "Порт $port ($proto) уже прослушивается другим процессом! Возможен конфликт."
            return 1
        fi
    fi
    return 0
}
