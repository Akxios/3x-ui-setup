#!/usr/bin/env bash

log "Status"

echo ""
echo "--- UFW ---"
ufw status verbose || true

echo ""
echo "--- Fail2Ban ---"
fail2ban-client status || true

echo ""
echo "--- nginx ---"
nginx -t || true
systemctl status nginx --no-pager -l || true

echo ""
echo "--- 3x-ui / x-ui ---"
systemctl status x-ui --no-pager -l || true

echo ""
echo "--- Listening ports ---"
ss -tulnp || true
