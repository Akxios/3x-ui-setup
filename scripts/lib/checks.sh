#!/usr/bin/env bash

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        fail "Run as root: sudo bash scripts/install.sh all"
    fi
}

require_apt_system() {
    if ! command -v apt-get >/dev/null 2>&1; then
        fail "This script currently supports Debian/Ubuntu-like systems with apt-get."
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
