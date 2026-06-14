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

xui_log="${LOG_DIR}/3x-ui-installer-$(date +%Y%m%d-%H%M%S).log"
xui_installer="$(mktemp)"
: > "$xui_log"
chmod 600 "$xui_log"

warn "Вывод официального installer будет сохранён: ${xui_log}"
append_log_header "3x-ui installer"

run_logged "Загрузка installer 3x-ui" curl -fsSL "$THREE_X_UI_INSTALL_URL" -o "$xui_installer"

installer_status=0
if bool_enabled "${XUI_INSTALL_VISIBLE:-true}"; then
    bash "$xui_installer" 2>&1 | tee "$xui_log" || installer_status=$?
else
    bash "$xui_installer" > "$xui_log" 2>&1 || installer_status=$?
fi
rm -f "$xui_installer"

cat "$xui_log" >> "$LOG_FILE"

if (( installer_status != 0 )); then
    warn "Официальный installer 3x-ui завершился с ошибкой. Последние строки:"
    tail -n 40 "$xui_log" || true
    fail "Установка 3x-ui не завершена"
fi

summary_section "3x-ui"
summary_add "Transcript installer: ${xui_log}"

if grep -Eai 'username|password|port|web|panel|login|user|pass|адрес|порт|логин|парол|https?://' "$xui_log" >/dev/null 2>&1; then
    summary_add "Важные строки installer:"
    grep -Eai 'username|password|port|web|panel|login|user|pass|адрес|порт|логин|парол|https?://' "$xui_log" | tail -n 40 >> "$SUMMARY_FILE"
else
    summary_add "В installer-логе не найдены строки с логином/паролем/портом."
fi

ok "Установка 3x-ui завершена"
