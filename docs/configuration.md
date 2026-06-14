# Конфигурация

В `.env.example` оставлены только поля, которые обычно нужно менять перед первым запуском.
Остальные значения можно не указывать: установщик подставит дефолты.

## Минимальный `.env`

```bash
DOMAIN="example.com"
LETSENCRYPT_EMAIL="admin@example.com"

ENABLE_WWW="false"
INSTALL_3X_UI="true"
XRAY_TCP_PORTS="8443"

EXTRA_TCP_PORTS=""
EXTRA_UDP_PORTS=""
```

## Полный пример `.env`

```bash
# Идентификация сервера
DOMAIN="example.com"
ENABLE_WWW="false"

# Nginx
ENABLE_NGINX="true"
WEB_ROOT="/var/www/${DOMAIN}/html"
NGINX_AUTO_HTTPS="true"
LETSENCRYPT_EMAIL="admin@example.com"
NGINX_USE_HTTPS="false"
NGINX_CERT_PATH="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
NGINX_CERT_KEY_PATH="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

# Firewall / UFW
ENABLE_UFW="true"
UFW_DEFAULT_INCOMING="deny"
UFW_DEFAULT_OUTGOING="allow"
UFW_RESET_RULES="false"
CURRENT_SSH_PORTS=""
LIMIT_SSH_PORT="true"
WEB_TCP_PORTS="80 443"
WEB_UDP_PORTS=""

# 3x-ui / Xray порты
ENABLE_3X_UI_PORTS="true"
XRAY_TCP_PORTS="8443"
XRAY_UDP_PORTS=""
XUI_PANEL_TCP_PORTS=""
EXTRA_TCP_PORTS=""
EXTRA_UDP_PORTS=""

# Fail2Ban
ENABLE_FAIL2BAN="true"
FAIL2BAN_BANTIME="1h"
FAIL2BAN_FINDTIME="10m"
FAIL2BAN_MAXRETRY="3"
FAIL2BAN_BANACTION="ufw"
FAIL2BAN_IGNORE_IPS="127.0.0.1/8 ::1"
ENABLE_NGINX_BOTSEARCH="true"

# Установка 3x-ui
INSTALL_3X_UI="true"
THREE_X_UI_INSTALL_URL="https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh"
XUI_INSTALL_VISIBLE="true"

# Удаление
REMOVE_WEB_ROOT="false"
REMOVE_CERTBOT_CERT="false"
REMOVE_FAIL2BAN_JAIL="false"
REMOVE_XUI_DATA="false"
PURGE_PACKAGES="false"
REMOVE_CONFIRM="false"

# Логи и итог
VERBOSE="false"
LOG_DIR="/var/log/vps-bootstrap"
SUMMARY_FILE="/root/vps-bootstrap-summary.txt"
```

`XUI_INSTALL_VISIBLE=true` оставляет вывод официального installer 3x-ui на экране, потому что он может быть интерактивным. При этом весь вывод сохраняется в отдельный transcript, а строки с логином, паролем, портом и URL добавляются в итоговый summary.

`VERBOSE=false` скрывает шум apt/ufw/systemctl/nginx/certbot-команд. При ошибке скрипт покажет последние строки лога.

`VERBOSE=true` полезен для диагностики: статус покажет полный `systemctl`, `nginx -t`, `fail2ban-client status` и список прослушиваемых портов.

## Удаление через bootstrap

Интерактивный выбор:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove
```

Удаление конкретного компонента:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove nginx
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove fail2ban
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove 3x-ui
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove ufw
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove all
```
