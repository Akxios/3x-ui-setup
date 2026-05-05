#!/usr/bin/env bash

log() {
    echo -e "\n\033[1;34m==> $*\033[0m"
}

ok() {
    echo -e "\033[1;32mOK:\033[0m $*"
}

warn() {
    echo -e "\033[1;33mWARN:\033[0m $*"
}

fail() {
    echo -e "\033[1;31mERROR:\033[0m $*" >&2
    exit 1
}

bool_enabled() {
    [[ "${1:-false}" == "true" ]]
}

backup_file() {
    local file="$1"
    local backup_dir="/root/vps-bootstrap-backups/$(date +%Y%m%d-%H%M%S)"

    if [[ -e "$file" ]]; then
        mkdir -p "$backup_dir"
        cp -a "$file" "$backup_dir/$(echo "$file" | sed 's#/#_#g')"
        ok "Backup saved: $file"
    fi
}

apt_update_once() {
    if [[ ! -f /tmp/vps-bootstrap-apt-updated ]]; then
        apt-get update
        touch /tmp/vps-bootstrap-apt-updated
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
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    else
        ok "Packages already installed: $*"
    fi
}
