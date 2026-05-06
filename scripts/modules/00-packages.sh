#!/usr/bin/env bash

log "Установка базовых пакетов"

packages=(
    nginx
    certbot
    ufw
    fail2ban
    curl
    wget
    ca-certificates
    gnupg
    lsb-release
)

install_packages_if_missing "${packages[@]}"

systemctl enable nginx >/dev/null 2>&1 || true
systemctl enable fail2ban >/dev/null 2>&1 || true

ok "Базовые пакеты готовы"
