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
