#!/usr/bin/env bash

bool_enabled "${ENABLE_UFW:-true}" || {
    warn "UFW module disabled"
    return 0
}

log "Configuring UFW firewall"

install_packages_if_missing ufw

ssh_ports="$(detect_ssh_ports)"

if [[ -z "${ssh_ports// }" ]]; then
    ssh_ports="22"
fi

warn "SSH ports to keep open: ${ssh_ports}"

ufw --force reset
ufw default "${UFW_DEFAULT_INCOMING:-deny}" incoming
ufw default "${UFW_DEFAULT_OUTGOING:-allow}" outgoing

for port in $ssh_ports; do
    [[ -z "$port" ]] && continue

    if bool_enabled "${LIMIT_SSH_PORT:-true}"; then
        ufw limit "${port}/tcp"
    else
        ufw allow "${port}/tcp"
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
    ufw allow "${port}/tcp"
done

for port in $udp_ports; do
    [[ -z "$port" ]] && continue
    ufw allow "${port}/udp"
done

ufw --force enable
ufw reload

ok "UFW configured"
ufw status verbose
