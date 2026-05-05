#!/usr/bin/env bash

bool_enabled "${ENABLE_NGINX:-true}" || {
    warn "nginx module disabled"
    return 0
}

log "Configuring nginx stub"

install_packages_if_missing nginx

issue_letsencrypt_cert() {
    local domains=("-d" "$DOMAIN")

    if bool_enabled "${ENABLE_WWW:-false}"; then
        domains+=("-d" "www.${DOMAIN}")
    fi

    if [[ -z "${LETSENCRYPT_EMAIL:-}" ]]; then
        fail "LETSENCRYPT_EMAIL is empty. Set it in .env to enable automatic HTTPS."
    fi

    install_packages_if_missing certbot

    certbot certonly \
        --webroot -w "$WEB_ROOT" \
        --non-interactive --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --keep-until-expiring \
        "${domains[@]}"

    ok "Let's Encrypt certificate issued/verified"
}


mkdir -p "$WEB_ROOT"

cat > "${WEB_ROOT}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${DOMAIN}</title>
    <style>
        body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            background: #0f172a;
            color: #e5e7eb;
        }
        main {
            text-align: center;
            padding: 32px;
        }
        h1 {
            margin: 0 0 8px;
            font-size: 42px;
        }
        p {
            margin: 0;
            opacity: .75;
        }
    </style>
</head>
<body>
    <main>
        <h1>${DOMAIN}</h1>
        <p>Server is running.</p>
    </main>
</body>
</html>
EOF

site_file="/etc/nginx/sites-available/${DOMAIN}"
enabled_file="/etc/nginx/sites-enabled/${DOMAIN}"

backup_file "$site_file"

if bool_enabled "${NGINX_AUTO_HTTPS:-true}"; then
    render_template \
        "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl" \
        "$site_file"

    ln -sf "$site_file" "$enabled_file"

    if [[ -e /etc/nginx/sites-enabled/default ]]; then
        rm -f /etc/nginx/sites-enabled/default
    fi

    nginx -t
    systemctl reload nginx || systemctl restart nginx

    issue_letsencrypt_cert

    render_template \
        "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl" \
        "$site_file"
elif bool_enabled "${NGINX_USE_HTTPS:-false}"; then
    if [[ ! -f "$NGINX_CERT_PATH" || ! -f "$NGINX_CERT_KEY_PATH" ]]; then
        fail "NGINX_USE_HTTPS=true, but cert files not found"
    fi

    render_template \
        "${PROJECT_DIR}/templates/nginx/stub-https.conf.tpl" \
        "$site_file"
else
    render_template \
        "${PROJECT_DIR}/templates/nginx/stub-http.conf.tpl" \
        "$site_file"
fi

ln -sf "$site_file" "$enabled_file"

if [[ -e /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
fi

nginx -t
systemctl reload nginx || systemctl restart nginx

ok "nginx configured for ${DOMAIN}"
