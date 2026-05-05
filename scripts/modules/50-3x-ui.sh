#!/usr/bin/env bash

bool_enabled "${INSTALL_3X_UI:-false}" || {
    warn "Установка 3x-ui отключена"
    return 0
}

log "Установка 3x-ui через официальный installer"

install_packages_if_missing curl ca-certificates

if systemctl list-unit-files | grep -q '^x-ui.service'; then
    warn "Сервис x-ui уже существует. Установка пропущена."
    warn "Используйте меню x-ui вручную для обновления или настройки."
    return 0
fi

bash <(curl -Ls "${THREE_X_UI_INSTALL_URL}")

ok "Установка 3x-ui завершена"
