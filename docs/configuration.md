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
THREE_X_UI_VERSION="v3.8.5"
# THREE_X_UI_INSTALL_URL по умолчанию берётся из тега THREE_X_UI_VERSION
XUI_AUTO_CONFIGURE="true"
# Для автонастройки обязательны ENABLE_UFW=true и UFW_DEFAULT_INCOMING=deny
XUI_INSTALL_VISIBLE="false"
XUI_PANEL_PORT="2053"
XUI_SUB_PORT="2096"

# Удаление
REMOVE_WEB_ROOT="false"
REMOVE_CERTBOT_CERT="false"
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
EXTRA_TCP_PORTS="1234 5678"
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

Каталог сайта. Если `index.html` отсутствует, сюда устанавливается интерактивная страница племени. При повторном запуске обновляется только страница с маркером проекта или прежняя неизменённая заглушка; пользовательский `index.html` сохраняется. Игровой прогресс хранится в `localStorage` браузера и не отправляется скриптом страницы на сервер. По умолчанию:

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
Перед запуском Certbot скрипт создаёт временный файл в `WEB_ROOT/.well-known/acme-challenge/` и проверяет его ответ через локальный nginx на `127.0.0.1:80`. Новые каталоги web-root создаются с правами, позволяющими nginx читать файлы. Если локальная проверка проходит, но Certbot отвечает `unauthorized`, проверьте публичные A/AAAA-записи, внешний firewall и ответ домена с другого компьютера: локальная проверка не подтверждает доступность сервера из интернета.

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

Список SSH-портов, которые нужно оставить открытыми. Если пусто, скрипт объединит порт текущего SSH-сеанса, сокеты `sshd`, `ssh.socket`/`sshd.socket` и `sshd -T`. Если ни один порт не определён, установка остановится до изменения UFW.

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

Порты, которые UFW разрешает для Xray/3x-ui inbound. По умолчанию разрешён `8443/tcp`. Это не создаёт inbound в панели: после создания клиента укажите в `XRAY_TCP_PORTS`/`XRAY_UDP_PORTS` его реальные порты и повторно запустите `sudo bash scripts/install.sh firewall`.

### `XUI_PANEL_TCP_PORTS`

Дополнительные порты для ручной схемы панели. По умолчанию пусто: при автонастройке внешний доступ идёт через nginx на 443/tcp, внутренние порты не открываются.

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

Если `true`, запускается официальный installer 3x-ui только при отсутствии установленного бинарного файла. Существующая панель сохраняется и настраивается через API.

### `THREE_X_UI_INSTALL_URL`

URL официального installer. По умолчанию он строится из `THREE_X_UI_VERSION`:

```bash
https://raw.githubusercontent.com/MHSanaei/3x-ui/v3.8.5/install.sh
```

### `THREE_X_UI_INSTALL_SHA256`

Ожидаемая SHA-256 сумма файла `install.sh`. Для закреплённой версии `v3.8.5` задана по умолчанию. Если меняете версию или URL, одновременно задайте сумму именно нового файла; при несовпадении установка прекращается до запуска скачанного скрипта.

### `XUI_INSTALL_VISIBLE`

По умолчанию `false`. В ручном режиме значение `true` показывает вопросы и вывод installer. В автоматическом режиме transcript всегда сохраняется отдельно с правами `600`; реквизиты выводятся в карточке доступа и не копируются в общий лог или summary.

Если `false`, вывод installer скрыт и сохраняется только в отдельный transcript. Автоматический режим не копирует этот transcript в общий лог установки.

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
REMOVE_XUI_DATA="true"
PURGE_PACKAGES="true"
REMOVE_CONFIRM="true"
```


## Автонастройка панели и подписок

После `sudo bash scripts/install.sh all` успешная установка выводит карточку доступа с такими адресами:

| Сервис | Адрес снаружи | Куда передаёт nginx |
| --- | --- | --- |
| Сайт | `https://DOMAIN/` | файлы `WEB_ROOT` |
| Панель | `https://DOMAIN/<случайный-путь>/` | 3x-ui: `127.0.0.1:2053` |
| Подписка | `https://DOMAIN/sub/<ID-клиента>` | 3x-ui: `127.0.0.1:2096` |

Для всех публичных HTTPS-адресов используется `443/tcp`, поэтому в URL не нужно указывать номер порта. `2053` и `2096` — настраиваемые внутренние порты; они не открываются наружу при автонастройке. Адрес подписки в карточке — шаблон: для реальной ссылки сначала создайте inbound и клиента в панели. Открытый по умолчанию `8443/tcp` сам по себе не создаёт inbound.

- `XUI_AUTO_CONFIGURE=true` — установка без вопросов, настройка через API и HTTPS через nginx. Требует `ENABLE_NGINX=true`, `ENABLE_UFW=true`, `UFW_DEFAULT_INCOMING=deny`, `UFW_DEFAULT_OUTGOING=allow`, `UFW_RESET_RULES=false` и `NGINX_AUTO_HTTPS=true` либо `NGINX_USE_HTTPS=true`.
- `THREE_X_UI_VERSION=v3.8.5` — закреплённая версия для новых установок. URL installer по умолчанию использует тот же тег. Изменение версии требует проверки совместимости API и нового значения `THREE_X_UI_INSTALL_SHA256`.
- `XUI_PANEL_PORT` — локальный порт панели, по умолчанию `2053`. Если не указан, повторный запуск использует сохранённый порт.
- `XUI_SUB_PORT` — локальный порт подписки, по умолчанию `2096`. Порты должны различаться и не занимать 80/443 или порты Xray/SSH.
- `XUI_WEB_BASE_PATH` — один сегмент пути панели (4–80 букв, цифр, `_`, `-`); по умолчанию генерируется и сохраняется.
- `XUI_USERNAME`, `XUI_PASSWORD` — для новой установки задают реквизиты вместо случайных. Для существующей панели должны совпадать с текущими: пароль автоматически не сбрасывается. Значения `.env` — Bash-код, поэтому пароли со спецсимволами заключайте в одинарные кавычки и задайте файлу права `600`.
- `XUI_STATE_FILE=/etc/3x-ui-setup/access.json` — постоянное состояние и реквизиты, права `600`.
- `XUI_ACCESS_FILE=/root/3x-ui-access.txt` — карточка после успешной проверки, права `600`. Команда `sudo bash scripts/install.sh access` собирает карточку из постоянного состояния даже без `.env` и честно показывает незавершённую проверку. Для нестандартного пути задайте `XUI_STATE_FILE` в окружении.

В автоматическом режиме `XUI_INSTALL_VISIBLE` не выводит transcript на экран: он может содержать пароли. Реквизиты выводятся отдельной карточкой в конце, после проверки HTTPS. В ручном режиме (`XUI_AUTO_CONFIGURE=false`) значение `true` позволяет видеть вопросы официального installer. В этом режиме автоматическая карточка не создаётся.

Подписки доступны через `/sub/`; маршруты `/subjson/` и `/subclash/` также проксируются, но соответствующие форматы нужно включить в панели при необходимости. Текущие клиенты и inbound сохраняются. Настройки панели и подписок привязываются к `127.0.0.1`, TLS завершается на nginx. В UFW автоматически разрешается `443/tcp`, а при полном запуске также `80/tcp` для Certbot. Firewall провайдера этим скриптом не управляется.

Перед изменением настроек API сохраняется `/etc/3x-ui-setup/settings-before.json` (рядом с `XUI_STATE_FILE`). Это снимок API для диагностики, а не полная резервная копия: API может скрывать секреты. Персональная ссылка подписки требует inbound и клиента; они автоматически не создаются.

## Защита автоматической установки

- Скачанный `install.sh` 3x-ui сверяется с `THREE_X_UI_INSTALL_SHA256`. Для закреплённой версии `v3.8.5` встроена проверенная сумма. При своей версии или URL задайте сумму соответствующего файла из доверенного источника. Сам официальный installer может загружать архивы и зависимости; он остаётся сторонним кодом с правами root.
- Локальные порты панели и подписки закрываются UFW правилом `deny`, которое ставится до запуска installer и сохраняется после настройки. Если UFW отключён, его политика incoming не `deny` или на сервере есть глобальный IPv6 при `IPV6=no`, автоматическая установка прекращается. Прямой доступ идёт только через nginx на `443/tcp`.
- Пользовательский `/etc/nginx/sites-available/DOMAIN` и `/etc/fail2ban/jail.local` не заменяются. Управляемый nginx-конфиг имеет маркер `# Managed by 3x-ui-setup`; собственный Fail2Ban jail находится в `/etc/fail2ban/jail.d/3x-ui-setup.local`. Проверка и перезапуск проходят с откатом при ошибке.
- `.env` автоматически получает права `600` до загрузки. Не передавайте его или карточку доступа другим пользователям сервера. Пароль также хранится в `/etc/3x-ui-setup/access.json` и в закрытом результате официального installer `/etc/x-ui/install-result.env`.
- Существующий домен с неуправляемым nginx-конфигом требует ручной миграции. Сначала проверьте его содержимое, затем добавьте маркер только если это старый конфиг проекта.
