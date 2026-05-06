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

    if command_exists sshd; then
        sshd -T 2>/dev/null | awk '/^port / {print $2}' | sort -n | uniq | tr '\n' ' '
        return 0
    fi

    echo "22"
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
        true|false|"")
            ;;
        *)
            fail "Переменная $name должна быть true или false, сейчас: $value"
            ;;
    esac
}

validate_domain() {
    local domain="$1"

    if [[ ! "$domain" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        fail "Некорректный DOMAIN: $domain"
    fi
}
