#!/usr/bin/env bash

log "Установка базовых пакетов"

packages=(
    curl
    wget
    ca-certificates
    gnupg
    lsb-release
)

if bool_enabled "${ENABLE_NGINX:-true}"; then
    packages+=(nginx certbot)
fi

if bool_enabled "${ENABLE_UFW:-true}"; then
    packages+=(ufw)
fi

if bool_enabled "${ENABLE_FAIL2BAN:-true}"; then
    packages+=(fail2ban)
fi

install_packages_if_missing "${packages[@]}"

if bool_enabled "${ENABLE_NGINX:-true}"; then
    systemctl enable nginx >/dev/null 2>&1 || true
fi

if bool_enabled "${ENABLE_FAIL2BAN:-true}"; then
    systemctl enable fail2ban >/dev/null 2>&1 || true
fi

ok "Базовые пакеты готовы"
