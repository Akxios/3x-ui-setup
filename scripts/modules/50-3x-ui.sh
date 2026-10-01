#!/usr/bin/env bash

bool_enabled "${INSTALL_3X_UI:-false}" || {
    warn "Установка 3x-ui отключена"
    return 0
}

log "Установка 3x-ui через официальный installer"

install_packages_if_missing curl ca-certificates

if [[ -x /usr/local/x-ui/x-ui ]]; then
    warn "Сервис x-ui уже существует. Установка пропущена."
    warn "Существующие реквизиты сохраняются; настройки проверит следующий модуль."
    return 0
fi

xui_log="${LOG_DIR}/3x-ui-installer-$(date +%Y%m%d-%H%M%S).log"
xui_installer="$(mktemp)"
: > "$xui_log"
chmod 600 "$xui_log"

warn "Вывод официального installer будет сохранён: ${xui_log}"
append_log_header "3x-ui installer"

run_logged "Загрузка installer 3x-ui" curl -fsSL "$THREE_X_UI_INSTALL_URL" -o "$xui_installer"
downloaded_sha="$(sha256sum "$xui_installer" | awk '{print $1}')"
if [[ "${downloaded_sha,,}" != "${THREE_X_UI_INSTALL_SHA256,,}" ]]; then
    rm -f "$xui_installer"
    fail "Контрольная сумма installer 3x-ui не совпала с THREE_X_UI_INSTALL_SHA256"
fi

installer_status=0
if bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    # Credentials are deliberately kept out of the general installation log.
    xui_setup install "$xui_installer" "$THREE_X_UI_VERSION" > "$xui_log" 2>&1 || installer_status=$?
elif bool_enabled "${XUI_INSTALL_VISIBLE:-false}"; then
    bash "$xui_installer" "$THREE_X_UI_VERSION" 2>&1 | tee "$xui_log" || installer_status=$?
else
    bash "$xui_installer" "$THREE_X_UI_VERSION" > "$xui_log" 2>&1 || installer_status=$?
fi
rm -f "$xui_installer"

if ! bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    cat "$xui_log" >> "$LOG_FILE"
fi

if (( installer_status != 0 )); then
    warn "Официальный installer завершился с ошибкой. Закрытый лог: $xui_log"
    warn "Сохранённые реквизиты: sudo bash scripts/install.sh access"
    fail "Установка 3x-ui не завершена"
fi

summary_section "3x-ui"
summary_add "Transcript installer: ${xui_log}"

if ! bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    summary_add "Реквизиты ищите в закрытом transcript installer."
fi

ok "Установка 3x-ui завершена"
