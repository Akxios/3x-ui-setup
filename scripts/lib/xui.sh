#!/usr/bin/env bash

xui_setup() {
    export DOMAIN XUI_STATE_FILE XUI_ACCESS_FILE XUI_PANEL_PORT XUI_SUB_PORT
    export XUI_USERNAME XUI_PASSWORD XUI_WEB_BASE_PATH XRAY_TCP_PORTS EXTRA_TCP_PORTS CURRENT_SSH_PORTS
    python3 "${SCRIPT_DIR}/lib/xui_setup.py" "$@"
}

prepare_xui() {
    bool_enabled "${INSTALL_3X_UI:-false}" || return 0
    bool_enabled "${XUI_AUTO_CONFIGURE:-true}" || return 0
    bool_enabled "$ENABLE_NGINX" || fail "XUI_AUTO_CONFIGURE требует ENABLE_NGINX=true"
    bool_enabled "$ENABLE_UFW" || fail "Автонастройка 3x-ui требует ENABLE_UFW=true для защиты панели до её локальной привязки"
    [[ "$UFW_DEFAULT_INCOMING" == deny ]] || fail "Автонастройка 3x-ui требует UFW_DEFAULT_INCOMING=deny"
    [[ "$UFW_DEFAULT_OUTGOING" == allow ]] || fail "Автонастройка 3x-ui требует UFW_DEFAULT_OUTGOING=allow для загрузки пакетов и сертификата"
    ! bool_enabled "$UFW_RESET_RULES" || fail "UFW_RESET_RULES=true создаёт окно без защиты; автонастройка его не допускает"
    if ! bool_enabled "$NGINX_AUTO_HTTPS" && ! bool_enabled "$NGINX_USE_HTTPS"; then
        fail "Автонастройке панели требуется HTTPS nginx"
    fi
    install_packages_if_missing python3
    log "Подготовка реквизитов и проверка настроек панели"
    xui_setup prepare
}

show_xui_access() {
    [[ -f "$XUI_STATE_FILE" ]] || fail "Сохранённых реквизитов нет: $XUI_STATE_FILE"
    xui_setup access
    printf '\nКарточка доступа: %s\n' "$XUI_ACCESS_FILE"
}
