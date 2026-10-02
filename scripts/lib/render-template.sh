#!/usr/bin/env bash

render_template() {
    local input_file="$1"
    local output_file="$2"

    if [[ ! -f "$input_file" ]]; then
        fail "Шаблон не найден: $input_file"
    fi

    mkdir -p "$(dirname "$output_file")"

    local rendered
    rendered="$(cat "$input_file")"

    local www_domain=""
    if bool_enabled "${ENABLE_WWW:-false}"; then
        www_domain="www.${DOMAIN}"
    fi

    local ssh_ports
    ssh_ports="$(detect_ssh_ports | xargs | tr ' ' ',')"

    rendered="${rendered//\{\{DOMAIN\}\}/${DOMAIN}}"
    rendered="${rendered//\{\{WWW_DOMAIN\}\}/${www_domain}}"
    rendered="${rendered//\{\{WEB_ROOT\}\}/${WEB_ROOT}}"
    rendered="${rendered//\{\{NGINX_CERT_PATH\}\}/${NGINX_CERT_PATH}}"
    rendered="${rendered//\{\{NGINX_CERT_KEY_PATH\}\}/${NGINX_CERT_KEY_PATH}}"
    rendered="${rendered//\{\{FAIL2BAN_BANTIME\}\}/${FAIL2BAN_BANTIME}}"
    rendered="${rendered//\{\{FAIL2BAN_FINDTIME\}\}/${FAIL2BAN_FINDTIME}}"
    rendered="${rendered//\{\{FAIL2BAN_MAXRETRY\}\}/${FAIL2BAN_MAXRETRY}}"
    rendered="${rendered//\{\{FAIL2BAN_BANACTION\}\}/${FAIL2BAN_BANACTION}}"
    rendered="${rendered//\{\{FAIL2BAN_IGNORE_IPS\}\}/${FAIL2BAN_IGNORE_IPS}}"
    rendered="${rendered//\{\{ENABLE_NGINX_BOTSEARCH\}\}/${ENABLE_NGINX_BOTSEARCH}}"
    rendered="${rendered//\{\{SSH_PORTS\}\}/${ssh_ports}}"

    local ipv6_http_listen="" ipv6_https_listen=""
    if [[ -r /proc/net/if_inet6 ]] && grep -q . /proc/net/if_inet6; then
        ipv6_http_listen="listen [::]:80;"
        ipv6_https_listen="listen [::]:443 ssl http2;"
    fi
    rendered="${rendered//\{\{NGINX_IPV6_HTTP_LISTEN\}\}/${ipv6_http_listen}}"
    rendered="${rendered//\{\{NGINX_IPV6_HTTPS_LISTEN\}\}/${ipv6_https_listen}}"

    local proxy_locations=""
    if [[ -f "${XUI_STATE_FILE:-/etc/3x-ui-setup/access.json}" ||
        ( "${XUI_PROXY_PENDING:-false}" == true &&
          -f "${XUI_STATE_FILE:-/etc/3x-ui-setup/access.json}.pending" ) ]]; then
        proxy_locations="$(xui_setup proxy)" || return 1
    fi
    rendered="${rendered//\{\{XUI_PROXY_LOCATIONS\}\}/${proxy_locations}}"

    printf '%s\n' "$rendered" > "$output_file"
}
