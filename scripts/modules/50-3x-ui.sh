#!/usr/bin/env bash

restore_xui_upgrade_backup() {
    [[ -n "${backup_dir:-}" && -d "$backup_dir" ]] || fail "Резервная копия обновления 3x-ui не найдена"
    warn "Восстановление предыдущей версии 3x-ui из $backup_dir"
    for original in /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service; do
        if [[ -e "$backup_dir$original" ]]; then
            if [[ -d "$backup_dir$original" ]]; then
                mkdir -p -- "$original"
                cp -a -- "$backup_dir$original/." "$original/" || fail "Не удалось восстановить $original; копия: $backup_dir"
            else
                cp -a -- "$backup_dir$original" "$original" || fail "Не удалось восстановить $original; копия: $backup_dir"
            fi
        fi
    done
    systemctl daemon-reload || fail "Не удалось обновить systemd после отката; копия: $backup_dir"
    systemctl restart x-ui || fail "Не удалось запустить прежнюю версию 3x-ui; копия: $backup_dir"
}

bool_enabled "${INSTALL_3X_UI:-false}" || {
    warn "Установка 3x-ui отключена"
    return 0
}

log "Установка 3x-ui через официальный installer"

install_packages_if_missing curl ca-certificates

if [[ -x /usr/local/x-ui/x-ui && "${XUI_UPGRADE_MODE:-false}" != true ]]; then
    warn "Сервис x-ui уже существует. Установка пропущена."
    warn "Существующие реквизиты сохраняются; настройки проверит следующий модуль."
    return 0
fi

if [[ "${XUI_UPGRADE_MODE:-false}" == true ]]; then
    [[ -x /usr/local/x-ui/x-ui ]] || fail "3x-ui ещё не установлен; используйте команду all"
    version_output="$(/usr/local/x-ui/x-ui -v 2>/dev/null)" || fail "Не удалось прочитать установленную версию 3x-ui"
    [[ "$version_output" =~ v?([0-9]+\.[0-9]+\.[0-9]+) ]] || fail "Не удалось определить установленную версию 3x-ui"
    installed_version="${BASH_REMATCH[1]}"
    if [[ "${installed_version#v}" == "${THREE_X_UI_VERSION#v}" ]]; then
        ok "3x-ui уже версии ${THREE_X_UI_VERSION}; повторная установка не нужна"
        return 0
    fi
    backup_root="/root/vps-bootstrap-backups"
    [[ ! -L "$backup_root" && ( ! -e "$backup_root" || -d "$backup_root" ) ]] || fail "Каталог резервных копий не должен быть symlink"
    if [[ -d "$backup_root" ]]; then
        [[ "$(stat -c %u "$backup_root")" == 0 ]] || fail "Каталог резервных копий должен принадлежать root"
    fi
    install -d -m 700 "$backup_root"
    backup_dir="/root/vps-bootstrap-backups/x-ui-upgrade-$(date +%Y%m%d-%H%M%S)-$$"
    [[ ! -e "$backup_dir" && ! -L "$backup_dir" ]] || fail "Каталог резервной копии уже существует"
    install -d -m 700 "$backup_dir"
    for original in /etc/x-ui /usr/local/x-ui /usr/bin/x-ui /etc/systemd/system/x-ui.service; do
        [[ ! -L "$original" ]] || fail "Невозможно обновить: $original является символьной ссылкой"
        if [[ -e "$original" ]]; then
            install -d -m 700 "$backup_dir$(dirname "$original")"
            cp -a -- "$original" "$backup_dir$original"
        fi
    done
    warn "Резервная копия 3x-ui: $backup_dir"
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
    warn "Ручной режим: installer может показать реквизиты панели в терминале; transcript хранится отдельно от общего лога"
    bash "$xui_installer" "$THREE_X_UI_VERSION" 2>&1 | tee "$xui_log" || installer_status=$?
else
    bash "$xui_installer" "$THREE_X_UI_VERSION" > "$xui_log" 2>&1 || installer_status=$?
fi
rm -f "$xui_installer"

if (( installer_status == 0 )) && [[ "${XUI_UPGRADE_MODE:-false}" == true ]]; then
    version_output="$(/usr/local/x-ui/x-ui -v 2>/dev/null)" || installer_status=1
    if [[ "$version_output" =~ v?([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        [[ "${BASH_REMATCH[1]}" == "${THREE_X_UI_VERSION#v}" ]] || installer_status=1
    else
        installer_status=1
    fi
fi

if (( installer_status != 0 )); then
    if [[ "${XUI_UPGRADE_MODE:-false}" == true ]]; then
        restore_xui_upgrade_backup
    fi
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
if [[ "${XUI_UPGRADE_MODE:-false}" == true ]]; then
    # Read by the caller after this module is sourced.
    # shellcheck disable=SC2034
    XUI_UPGRADE_APPLIED=true
fi
