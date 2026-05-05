#!/usr/bin/env bash

bool_enabled "${INSTALL_3X_UI:-false}" || {
    warn "3x-ui installation disabled"
    return 0
}

log "Installing 3x-ui using official installer"

install_packages_if_missing curl ca-certificates

if systemctl list-unit-files | grep -q '^x-ui.service'; then
    warn "x-ui service already exists. Skipping installer."
    warn "Use x-ui menu manually if you want to update or reconfigure it."
    return 0
fi

bash <(curl -Ls "${THREE_X_UI_INSTALL_URL}")

ok "3x-ui installer finished"
