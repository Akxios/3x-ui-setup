#!/usr/bin/env bash

log "Installing base packages"

install_packages_if_missing \
    nginx \
    certbot \
    ufw \
    fail2ban \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release

systemctl enable nginx >/dev/null 2>&1 || true
systemctl enable fail2ban >/dev/null 2>&1 || true

ok "Base packages are ready"
