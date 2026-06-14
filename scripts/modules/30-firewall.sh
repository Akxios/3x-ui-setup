#!/usr/bin/env bash

bool_enabled "${ENABLE_UFW:-true}" || {
    warn "Модуль UFW отключён"
    return 0
}

log "Настройка firewall UFW"

install_packages_if_missing ufw

ssh_ports="$(detect_ssh_ports)"

if [[ -z "${ssh_ports// }" ]]; then
    ssh_ports="22"
fi

warn "SSH-порты, которые будут оставлены открытыми: ${ssh_ports}"

if bool_enabled "${UFW_RESET_RULES:-false}"; then
    warn "Будут сброшены все текущие правила UFW"
    run_logged "Сброс правил UFW" ufw --force reset
else
    warn "Сброс UFW пропущен. Для полного сброса укажите UFW_RESET_RULES=true"
fi

run_logged "Политика UFW incoming=${UFW_DEFAULT_INCOMING:-deny}" ufw default "${UFW_DEFAULT_INCOMING:-deny}" incoming
run_logged "Политика UFW outgoing=${UFW_DEFAULT_OUTGOING:-allow}" ufw default "${UFW_DEFAULT_OUTGOING:-allow}" outgoing

validate_port() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        fail "Некорректный порт: $port"
    fi

    if (( port < 1 || port > 65535 )); then
        fail "Порт вне диапазона 1-65535: $port"
    fi
}

for port in $ssh_ports; do
    [[ -z "$port" ]] && continue
    validate_port "$port"

    if bool_enabled "${LIMIT_SSH_PORT:-true}"; then
        run_logged "UFW limit ${port}/tcp" ufw limit "${port}/tcp"
    else
        run_logged "UFW allow ${port}/tcp" ufw allow "${port}/tcp"
    fi
done

tcp_ports="${WEB_TCP_PORTS:-80 443} ${EXTRA_TCP_PORTS:-}"
udp_ports="${WEB_UDP_PORTS:-} ${EXTRA_UDP_PORTS:-}"

if bool_enabled "${ENABLE_3X_UI_PORTS:-true}"; then
    tcp_ports="$tcp_ports ${XRAY_TCP_PORTS:-} ${XUI_PANEL_TCP_PORTS:-}"
    udp_ports="$udp_ports ${XRAY_UDP_PORTS:-}"
fi

for port in $tcp_ports; do
    [[ -z "$port" ]] && continue
    validate_port "$port"
    check_port_free "$port" "tcp" || true
    run_logged "UFW allow ${port}/tcp" ufw allow "${port}/tcp"
done

for port in $udp_ports; do
    [[ -z "$port" ]] && continue
    validate_port "$port"
    check_port_free "$port" "udp" || true
    run_logged "UFW allow ${port}/udp" ufw allow "${port}/udp"
done

run_logged "Включение UFW" ufw --force enable
run_logged "Перезагрузка UFW" ufw reload

summary_section "Firewall"
summary_add "SSH порты: ${ssh_ports}"
summary_add "TCP порты: $(echo "$tcp_ports" | xargs)"
summary_add "UDP порты: $(echo "$udp_ports" | xargs)"
ok "UFW настроен"
if bool_enabled "${VERBOSE:-false}"; then
    ufw status verbose
fi
