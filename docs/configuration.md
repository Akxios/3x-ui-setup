# Настройки `.env`

[README](../README.md) · [Установка](installation.md) · [Эксплуатация](operations.md) · [Безопасность](security.md)

Конфигурация проекта хранится в `.env`. В `.env.example` оставлены только поля, которые обычно нужно менять перед первым запуском. Остальные значения можно не указывать: `scripts/install.sh` подставит дефолты во время выполнения.

`.env` читается как данные: одна настройка `KEY=VALUE` на строку, допускаются кавычки и комментарии. Команды Bash, `source`, подстановка команд и произвольные переменные не исполняются. Поддерживаются только настройки из этого справочника. `${DOMAIN}` подставляется только в `WEB_ROOT`, `NGINX_CERT_PATH` и `NGINX_CERT_KEY_PATH`. Старые `.env` с Bash-конструкциями нужно привести к обычным значениям перед повторным запуском. Для безопасного чтения файла нужен Python 3; bootstrap устанавливает его автоматически.

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

Разделы справочника: [формат значений](#правила-значений), [домен](#идентификация-сервера), [nginx и TLS](#nginx-и-tls), [UFW](#firewall--ufw), [Fail2Ban](#fail2ban), [3x-ui](#установка-3x-ui), [панель и подписки](#автонастройка-панели-и-подписок), [удаление](#удаление), [логи](#логи-summary-и-диагностика).

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

<details>
<summary>Расширенный пример `.env`</summary>

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

</details>

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
Перед запуском Certbot скрипт создаёт временный файл в `WEB_ROOT/.well-known/acme-challenge/` и проверяет его ответ через локальный nginx на `127.0.0.1:80` и, если IPv6 доступен, на `[::1]:80`. Проверяются все имена сертификата, включая `www` при `ENABLE_WWW=true`. Новые каталоги web-root создаются с правами, позволяющими nginx читать файлы. Если локальная проверка проходит, но Certbot отвечает `unauthorized`, проверьте публичные A/AAAA-записи, внешний firewall и ответ домена с другого компьютера: локальная проверка не подтверждает доступность сервера из интернета. После ошибки временный конфиг откатывается, поэтому последующий `nginx -T` может не показывать его.

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

### `THREE_X_UI_VERSION`

По умолчанию `v3.8.5`. При смене версии нужны совместимый API, URL и новый `THREE_X_UI_INSTALL_SHA256`. Если API старой версии не поддерживает JSON/Clash-настройки, автонастройка остановится до изменения панели.

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

## Автонастройка панели и подписок

По умолчанию `XUI_AUTO_CONFIGURE=true`: панель и три формата подписки настраиваются через API и публикуются на `https://DOMAIN/` с отдельными путями. Нужны `ENABLE_NGINX=true`, `ENABLE_UFW=true`, `UFW_DEFAULT_INCOMING=deny`, `UFW_DEFAULT_OUTGOING=allow`, `UFW_RESET_RULES=false` и готовый HTTPS.

При `XUI_AUTO_CONFIGURE=false` установщик не настраивает панель через API и не создаёт новую карточку доступа. Этот флаг не отменяет настройки и маршруты nginx, уже применённые при предыдущем запуске.

| Настройка | Назначение |
| --- | --- |
| `XUI_PANEL_PORT` | Локальный порт панели, по умолчанию `2053` |
| `XUI_SUB_PORT` | Локальный порт подписок, по умолчанию `2096`; не должен совпадать с портом панели, SSH, Xray или 80/443 |
| `XUI_WEB_BASE_PATH` | Один сегмент пути панели из 4–80 букв, цифр, `_`, `-`; по умолчанию случайный |
| `XUI_USERNAME`, `XUI_PASSWORD` | Реквизиты новой панели или текущие реквизиты существующей; без них новые генерируются случайно |
| `XUI_STATE_FILE` | Закрытое состояние и реквизиты, по умолчанию `/etc/3x-ui-setup/access.json` |
| `XUI_ACCESS_FILE` | Закрытая карточка после проверки, по умолчанию `/root/3x-ui-access.txt` |

Для новой панели генерируются три независимых случайных пути подписок. Они сохраняются в `access.json` и используются nginx; существующие пути сохраняются, чтобы не менять выданные ссылки. Панель и подписки слушают только `127.0.0.1`, TLS завершается на nginx. Проверка установки подтверждает маршрут до сервиса подписок, но не содержимое персональной ссылки без созданного клиента.

## Удаление

Команды и порядок удаления описаны в [эксплуатации](operations.md#удаление). Здесь перечислены флаги, меняющие поведение удаления.

### `REMOVE_WEB_ROOT`

Если `true`, при удалении nginx будет удалён только стандартный `/var/www/DOMAIN/html`, если в нём есть страница проекта и нет пользовательских файлов или символьных ссылок в пути. Нестандартный `WEB_ROOT` скрипт не удаляет. По умолчанию web-root сохраняется.

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
