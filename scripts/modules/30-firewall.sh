#!/usr/bin/env bash

bool_enabled "${ENABLE_UFW:-true}" || {
    warn "Модуль UFW отключён"
    return 0
}

log "Настройка firewall UFW"
install_packages_if_missing ufw iproute2
if command_exists ip && ip -6 -o addr show scope global 2>/dev/null | grep -q 'inet6 ' &&
    ! grep -Eq '^[[:space:]]*IPV6=yes([[:space:]]|$)' /etc/default/ufw; then
    fail "Сервер имеет глобальный IPv6, но UFW IPV6=yes не включён. Исправьте /etc/default/ufw до установки"
fi

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || fail "Некорректный порт: $port"
}

sync_xray_ufw_rules() {
    local line rule port protocol comment status
    local -A desired=() managed=() existing=()
    for port in $xray_tcp_ports; do desired["$port/tcp"]=1; done
    for port in $xray_udp_ports; do desired["$port/udp"]=1; done
    status="$(ufw status)" || fail "Не удалось прочитать правила UFW"
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]+)/(tcp|udp)[[:space:]] ]]; then
            port="${BASH_REMATCH[1]}"
            protocol="${BASH_REMATCH[2]}"
            rule="$port/$protocol"
            if [[ "$line" == *"ALLOW IN"* && "$line" == *"3x-ui-setup-xray-${port}-${protocol}" ]]; then
                managed["$rule"]=1
            elif [[ "$line" == *"ALLOW IN"* ]]; then
                existing["$rule"]=1
            fi
        fi
    done <<< "$status"

    for rule in "${!desired[@]}"; do
        [[ -z "${managed[$rule]:-}" ]] || continue
        if [[ -n "${existing[$rule]:-}" ]]; then
            warn "Правило UFW для $rule уже существует без метки проекта; оно сохранено"
            continue
        fi
        port="${rule%/*}"
        protocol="${rule#*/}"
        comment="3x-ui-setup-xray-${port}-${protocol}"
        run_logged "UFW allow $rule для Xray" ufw allow "$rule" comment "$comment"
        status="$(ufw status)" || fail "Не удалось проверить правило UFW для $rule"
        [[ "$status" == *"$comment"* ]] || fail "UFW не сохранил правило $rule с меткой проекта"
    done

    for rule in "${!managed[@]}"; do
        [[ -z "${desired[$rule]:-}" ]] || continue
        port="${rule%/*}"
        protocol="${rule#*/}"
        if [[ "$protocol" == tcp && " $tcp_ports $ssh_ports " == *" $port "* ]] ||
            [[ "$protocol" == udp && " $udp_ports " == *" $port "* ]]; then
            warn "Правило Xray $rule оставлено: порт всё ещё нужен другому компоненту"
            continue
        fi
        run_logged "Удаление устаревшего правила Xray $rule" ufw --force delete allow "$rule"
        comment="3x-ui-setup-xray-${port}-${protocol}"
        status="$(ufw status)" || fail "Не удалось проверить удаление правила UFW для $rule"
        if [[ "$status" == *"$comment"* ]]; then
            fail "Устаревшее правило Xray $rule осталось в UFW; проверьте его вручную"
        fi
    done
}

ssh_ports="$(detect_ssh_ports)"
[[ -n "${ssh_ports// }" ]] || fail "SSH-порты не определены. Задайте CURRENT_SSH_PORTS"
for port in $ssh_ports; do validate_port "$port"; done
warn "SSH-порты, которые будут оставлены открытыми: ${ssh_ports}"

tcp_ports="${WEB_TCP_PORTS:-80 443} ${EXTRA_TCP_PORTS:-}"
udp_ports="${WEB_UDP_PORTS:-} ${EXTRA_UDP_PORTS:-}"
xray_tcp_ports=""
xray_udp_ports=""
if bool_enabled "${INSTALL_3X_UI:-false}" && bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    ! bool_enabled "${UFW_RESET_RULES:-false}" || fail "Автонастройка запрещает UFW_RESET_RULES=true"
    [[ "${UFW_DEFAULT_INCOMING:-deny}" == deny && "${UFW_DEFAULT_OUTGOING:-allow}" == allow ]] || fail "Автонастройка требует UFW incoming=deny и outgoing=allow"
    tcp_ports="$tcp_ports 80 443"
fi
if bool_enabled "${ENABLE_3X_UI_PORTS:-true}"; then
    tcp_ports="$tcp_ports ${XUI_PANEL_TCP_PORTS:-}"
    xray_tcp_ports="${XRAY_TCP_PORTS:-}"
    xray_udp_ports="${XRAY_UDP_PORTS:-}"
    if bool_enabled "${INSTALL_3X_UI:-false}" && bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
        inbound_ports="$(xui_setup inbound-ports)" || fail "Не удалось прочитать inbound панели; правила UFW не менялись"
        for port in $inbound_ports; do
            validate_port "$port"
            inbound_listening=false
            if ss -H -ltnp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $4 !~ /^(127\.|\[::1\]|::1:)/ && /"xray[^"]*"/ {found=1} END {exit !found}'; then
                xray_tcp_ports="$xray_tcp_ports $port"
                inbound_listening=true
            fi
            if ss -H -lunp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $4 !~ /^(127\.|\[::1\]|::1:)/ && /"xray[^"]*"/ {found=1} END {exit !found}'; then
                xray_udp_ports="$xray_udp_ports $port"
                inbound_listening=true
            fi
            [[ "$inbound_listening" == true ]] || fail "Inbound $port включён, но Xray не слушает публичный адрес; правила UFW не менялись"
        done
    fi
fi

# Check all input before resetting or changing active firewall policies.
for port in $tcp_ports $udp_ports $xray_tcp_ports $xray_udp_ports; do validate_port "$port"; done
if bool_enabled "${INSTALL_3X_UI:-false}" && bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    xui_ports="$(xui_setup ports)" || fail "Не удалось прочитать локальные порты 3x-ui"
    read -r panel_port sub_port <<< "$xui_ports"
    for port in "$panel_port" "$sub_port"; do
        validate_port "$port"
        if command_exists ss && ss -H -ltnp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $0 !~ /"x-ui"/ {found=1} END {exit !found}'; then
            fail "Порт $port/tcp занят другим сервисом: отклонена привязка панели/подписки"
        fi
    done
fi
for port in 80 443; do
    if [[ " $tcp_ports " == *" $port "* ]] && command_exists ss &&
        ss -H -ltnp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $0 !~ /"nginx"/ {found=1} END {exit !found}'; then
        fail "Порт $port/tcp занят не nginx: отклонено открытие UFW"
    fi
done
for port in $xray_tcp_ports; do
    if command_exists ss && ss -H -ltnp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $0 !~ /"xray[^"]*"/ {found=1} END {exit !found}'; then
        fail "Порт $port/tcp занят другим сервисом: отклонено открытие UFW"
    fi
done
for port in $xray_udp_ports; do
    if command_exists ss && ss -H -lunp 2>/dev/null | awk -v target=":$port" '$4 ~ target"$" && $0 !~ /"xray[^"]*"/ {found=1} END {exit !found}'; then
        fail "Порт $port/udp занят другим сервисом: отклонено открытие UFW"
    fi
done

ufw_was_active=false
if ufw status | grep -q '^Status: active'; then ufw_was_active=true; fi

if bool_enabled "${UFW_RESET_RULES:-false}"; then
    warn "Сброс текущих правил UFW по UFW_RESET_RULES=true"
    run_logged "Сброс правил UFW" ufw --force reset
fi
run_logged "Политика UFW incoming=${UFW_DEFAULT_INCOMING:-deny}" ufw default "${UFW_DEFAULT_INCOMING:-deny}" incoming
run_logged "Политика UFW outgoing=${UFW_DEFAULT_OUTGOING:-allow}" ufw default "${UFW_DEFAULT_OUTGOING:-allow}" outgoing

for port in $ssh_ports; do
    if bool_enabled "${LIMIT_SSH_PORT:-true}"; then
        run_logged "UFW limit ${port}/tcp" ufw limit "${port}/tcp"
    else
        run_logged "UFW allow ${port}/tcp" ufw allow "${port}/tcp"
    fi
done
for port in $tcp_ports; do run_logged "UFW allow ${port}/tcp" ufw allow "${port}/tcp"; done
for port in $udp_ports; do run_logged "UFW allow ${port}/udp" ufw allow "${port}/udp"; done

# The official noninteractive installer initially binds the panel publicly.
# An early DENY takes precedence over an old ALLOW rule. Keep it afterwards
# so a future panel misconfiguration cannot expose its plain HTTP listener.
if bool_enabled "${INSTALL_3X_UI:-false}" && bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    for port in "$panel_port" "$sub_port"; do
        validate_port "$port"
        if ! ufw status | grep -Fq "3x-ui-setup-local-only-$port"; then
            run_logged "Закрытие прямого доступа к $port/tcp" ufw insert 1 deny "$port/tcp" comment "3x-ui-setup-local-only-$port"
        fi
    done
fi

run_logged "Включение UFW" ufw --force enable
sync_xray_ufw_rules
run_logged "Перезагрузка UFW" ufw reload
ufw_status="$(ufw status)"
printf '%s\n' "$ufw_status" | grep -q '^Status: active' || fail "UFW не активен после настройки"
if [[ "$ufw_was_active" == false ]]; then
    marker_dir="/etc/3x-ui-setup"
    marker_file="$marker_dir/ufw-enabled-by-project"
    [[ ! -L "$marker_dir" && ! -L "$marker_file" ]] || fail "Маркер UFW не должен быть символьной ссылкой"
    install -d -m 700 "$marker_dir"
    : > "$marker_file"
    chmod 600 "$marker_file"
fi
if bool_enabled "${INSTALL_3X_UI:-false}" && bool_enabled "${XUI_AUTO_CONFIGURE:-true}"; then
    for port in "$panel_port" "$sub_port"; do
        printf '%s\n' "$ufw_status" | grep -Fq "3x-ui-setup-local-only-$port" || fail "UFW не содержит запрет прямого доступа к $port/tcp"
    done
fi

summary_section "Firewall"
summary_add "SSH порты: ${ssh_ports}"
summary_add "TCP порты: $(echo "$tcp_ports $xray_tcp_ports" | xargs)"
summary_add "UDP порты: $(echo "$udp_ports $xray_udp_ports" | xargs)"
ok "UFW настроен"
if bool_enabled "${VERBOSE:-false}"; then ufw status verbose; fi
