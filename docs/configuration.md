# Конфигурация

Конфигурация проекта хранится в `.env`. В `.env.example` оставлены только поля, которые обычно нужно менять перед первым запуском. Остальные значения можно не указывать: `scripts/install.sh` подставит дефолты во время выполнения.

Перед первым запуском:

```bash
cp .env.example .env
nano .env
```

Минимально нужно заменить домен и email:

```bash
DOMAIN="example.com"
LETSENCRYPT_EMAIL="admin@example.com"
```

`DOMAIN` не должен оставаться `example.com`: установщик остановится перед установкой.

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
# SUMMARY_FILE="/root/vps-bootstrap-summary.txt"
```

## Правила значений

Boolean-переменные принимают значения:

```text
true, false, yes, no, 1, 0, on, off
```

Порты указываются числами от `1` до `65535`. Несколько портов перечисляются через пробел:

```bash
XRAY_TCP_PORTS="8443 9443"
EXTRA_TCP_PORTS="2053 2083"
```

Домен должен быть полноценным доменным именем, например `example.org` или `vpn.example.org`.

## Идентификация сервера

### `DOMAIN`

Основной домен сервера. Используется для:

- имени nginx-конфига `/etc/nginx/sites-available/${DOMAIN}`;
- web-root по умолчанию `/var/www/${DOMAIN}/html`;
- выпуска Let's Encrypt сертификата;
- итогового summary установки.

### `ENABLE_WWW`

Если `true`, Certbot запросит сертификат не только для `DOMAIN`, но и для `www.${DOMAIN}`. DNS-запись `www` должна заранее указывать на этот сервер.

## Nginx и TLS

### `ENABLE_NGINX`

Включает модуль nginx. Если `false`, установщик пропустит настройку web-root, nginx-конфига и TLS.

### `WEB_ROOT`

Каталог, куда будет записана HTML-заглушка. По умолчанию:

```bash
/var/www/${DOMAIN}/html
```

### `NGINX_AUTO_HTTPS`

Если `true`, установщик:

1. создаёт временный HTTP-конфиг nginx;
2. проверяет и перезагружает nginx;
3. выпускает сертификат через Certbot webroot;
4. заменяет конфиг на HTTPS-версию;
5. снова проверяет и перезагружает nginx.

Для этого домен должен указывать на сервер, а порты `80/tcp` и `443/tcp` должны быть доступны извне.

### `LETSENCRYPT_EMAIL`

Email для регистрации Let's Encrypt. Обязателен, если включён `NGINX_AUTO_HTTPS=true`.

### `NGINX_USE_HTTPS`

Используется, если сертификат уже существует и выпускать новый не нужно. Нельзя одновременно включать `NGINX_AUTO_HTTPS=true` и `NGINX_USE_HTTPS=true`: установщик остановится с ошибкой.

### `NGINX_CERT_PATH` и `NGINX_CERT_KEY_PATH`

Пути к готовому сертификату и приватному ключу. При `NGINX_USE_HTTPS=true` оба файла должны существовать.

Пути по умолчанию:

```bash
/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
/etc/letsencrypt/live/${DOMAIN}/privkey.pem
```

## Firewall / UFW

### `ENABLE_UFW`

Включает настройку UFW. Если `false`, firewall-модуль будет пропущен.

### `UFW_DEFAULT_INCOMING` и `UFW_DEFAULT_OUTGOING`

Политики UFW по умолчанию. Стандартная безопасная схема:

```bash
UFW_DEFAULT_INCOMING="deny"
UFW_DEFAULT_OUTGOING="allow"
```

### `UFW_RESET_RULES`

Если `true`, перед настройкой будет выполнен `ufw --force reset`. Это удалит текущие UFW-правила. По умолчанию `false`, чтобы не стереть ручные настройки.

### `CURRENT_SSH_PORTS`

Список SSH-портов, которые нужно оставить открытыми. Если пусто, скрипт попытается определить SSH-порты через `sshd -T`; если это не получится, использует `22`.

Пример:

```bash
CURRENT_SSH_PORTS="22 2222"
```

### `LIMIT_SSH_PORT`

Если `true`, для SSH используется `ufw limit`, а не обычный `ufw allow`. Это снижает риск простого brute-force по SSH.

### `WEB_TCP_PORTS` и `WEB_UDP_PORTS`

Порты web-сервисов. По умолчанию открываются:

```bash
WEB_TCP_PORTS="80 443"
WEB_UDP_PORTS=""
```

### `ENABLE_3X_UI_PORTS`

Если `true`, firewall-модуль добавит к разрешённым портам значения из `XRAY_TCP_PORTS`, `XRAY_UDP_PORTS` и `XUI_PANEL_TCP_PORTS`.

### `XRAY_TCP_PORTS` и `XRAY_UDP_PORTS`

Порты для Xray/3x-ui inbound. По умолчанию открыт `8443/tcp`.

### `XUI_PANEL_TCP_PORTS`

Порты панели 3x-ui. По умолчанию пусто: внешний доступ к панели не открывается автоматически.

### `EXTRA_TCP_PORTS` и `EXTRA_UDP_PORTS`

Дополнительные порты для ваших сервисов.

## Fail2Ban

### `ENABLE_FAIL2BAN`

Включает установку и настройку Fail2Ban.

### `FAIL2BAN_BANTIME`, `FAIL2BAN_FINDTIME`, `FAIL2BAN_MAXRETRY`

Основные параметры jail:

- `FAIL2BAN_BANTIME` — срок блокировки;
- `FAIL2BAN_FINDTIME` — окно времени для подсчёта попыток;
- `FAIL2BAN_MAXRETRY` — число попыток до блокировки.

### `FAIL2BAN_BANACTION`

Действие блокировки. По умолчанию используется `ufw`.

### `FAIL2BAN_IGNORE_IPS`

IP-адреса и подсети, которые Fail2Ban не должен блокировать.

### `ENABLE_NGINX_BOTSEARCH`

Если `true`, в шаблоне Fail2Ban включается jail для nginx botsearch.

## Установка 3x-ui

### `INSTALL_3X_UI`

Если `true`, будет запущен официальный installer 3x-ui. Если сервис `x-ui.service` уже существует, модуль пропустит установку и покажет предупреждение.

### `THREE_X_UI_INSTALL_URL`

URL официального installer. По умолчанию:

```bash
https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
```

### `XUI_INSTALL_VISIBLE`

Если `true`, вывод официального installer остаётся на экране, потому что он может быть интерактивным. При этом весь вывод сохраняется в отдельный transcript, а строки с логином, паролем, портом и URL добавляются в итоговый summary.

Если `false`, вывод installer будет скрыт и сохранён только в лог.

## Удаление

Команда удаления:

```bash
sudo bash scripts/install.sh remove
```

Или конкретный компонент:

```bash
sudo bash scripts/install.sh remove nginx
sudo bash scripts/install.sh remove fail2ban
sudo bash scripts/install.sh remove 3x-ui
sudo bash scripts/install.sh remove ufw
sudo bash scripts/install.sh remove all
```

### `REMOVE_WEB_ROOT`

Если `true`, при удалении nginx будет удалён `WEB_ROOT`. По умолчанию web-root сохраняется.

### `REMOVE_CERTBOT_CERT`

Если `true`, при удалении nginx будет выполнено удаление сертификата Certbot для `DOMAIN`.

### `REMOVE_FAIL2BAN_JAIL`

Если `true`, `/etc/fail2ban/jail.local` будет удалён без marker-проверки. По умолчанию скрипт удаляет этот файл только если он похож на управляемый проектом файл.

### `REMOVE_XUI_DATA`

Если `true`, при удалении 3x-ui будет удалён каталог `/etc/x-ui`. По умолчанию данные 3x-ui сохраняются.

### `PURGE_PACKAGES`

Если `true`, после удаления компонентов будут удалены связанные apt-пакеты через `apt-get purge` и `apt-get autoremove`.

### `REMOVE_CONFIRM`

Если `true`, удаление не будет спрашивать интерактивное подтверждение. Используйте только в автоматизации и только после проверки `.env`.

## Логи, summary и диагностика

### `VERBOSE`

Если `false`, установщик показывает короткий прогресс, а подробный вывод команд пишет в лог. При ошибке будут показаны последние 40 строк лога.

Если `true`, вывод команд будет показан в терминале и записан в лог. Для `status` это также включает:

- `fail2ban-client status`;
- `nginx -t`;
- `systemctl status nginx`;
- `systemctl status x-ui`;
- список прослушиваемых портов через `ss`.

`VERBOSE` загружается из `.env`. Если в `.env` уже указано `VERBOSE="false"`, одноразовая переменная окружения перед командой не переопределит это значение.

### `LOG_DIR`

Каталог логов. По умолчанию:

```bash
/var/log/vps-bootstrap
```

### `SUMMARY_FILE`

Файл итогового summary. Для основной установки по умолчанию:

```bash
/root/vps-bootstrap-summary.txt
```

Для команд `status` и `remove` скрипт создаёт timestamped summary в `LOG_DIR`, если явно не задан другой `SUMMARY_FILE`.

## Типовые сценарии

### Автоматический HTTPS

```bash
DOMAIN="example.org"
LETSENCRYPT_EMAIL="admin@example.org"
NGINX_AUTO_HTTPS="true"
NGINX_USE_HTTPS="false"
```

### Уже существующий сертификат

```bash
NGINX_AUTO_HTTPS="false"
NGINX_USE_HTTPS="true"
NGINX_CERT_PATH="/etc/letsencrypt/live/example.org/fullchain.pem"
NGINX_CERT_KEY_PATH="/etc/letsencrypt/live/example.org/privkey.pem"
```

### Не открывать порт панели 3x-ui

```bash
XUI_PANEL_TCP_PORTS=""
```

### Открыть порт панели вручную

```bash
XUI_PANEL_TCP_PORTS="2053"
```

### Сохранить ручные UFW-правила

```bash
UFW_RESET_RULES="false"
CURRENT_SSH_PORTS="22"
```

### Жёсткое удаление управляемых компонентов

```bash
REMOVE_WEB_ROOT="true"
REMOVE_CERTBOT_CERT="true"
REMOVE_FAIL2BAN_JAIL="true"
REMOVE_XUI_DATA="true"
PURGE_PACKAGES="true"
REMOVE_CONFIRM="true"
```
