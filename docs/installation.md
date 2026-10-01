# Установка сервера

[README](../README.md) · [Настройки `.env`](configuration.md) · [Эксплуатация](operations.md) · [Безопасность](security.md)

## 1. Подготовьте VPS и домен

- Нужен Debian/Ubuntu с `apt-get`, root-доступ или `sudo` и доступ к GitHub, apt и Let's Encrypt.
- A-запись домена должна вести на VPS. Если есть AAAA-запись, IPv6 тоже должен вести на этот сервер.
- Снаружи должны быть доступны `80/tcp` для HTTP-01 Certbot и `443/tcp` для HTTPS.
- Узнайте фактический SSH-порт и сохраните резервный вход через консоль провайдера. Установщик не меняет SSH-настройки.
- Для прямого запуска `scripts/install.sh` нужен Python 3; bootstrap установит его сам.

Если UFW уже настроен вручную, перед запуском проверьте `CURRENT_SSH_PORTS`, `UFW_RESET_RULES` и дополнительные порты в [справочнике](configuration.md#firewall--ufw).

## 2. Выберите способ запуска

### Обычная установка: одна команда

```bash
curl -fsSLo bootstrap.sh https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh && sudo bash bootstrap.sh install
```

Bootstrap установит базовые утилиты, создаст `/opt/3x-ui-setup/.env` и спросит домен, email и несколько базовых настроек. После подтверждения он выполнит установку. SHA вводить не нужно. Команда загружает актуальный `main` и сразу запускает его от root; если хотите проверить код до запуска, скачайте `bootstrap.sh` отдельно.

### Установка по конкретному коммиту

Замените значение `SHA` на полный 40-символьный SHA проверенного коммита. Файл bootstrap и checkout проекта должны иметь один и тот же SHA:

```bash
SHA="PASTE_40_CHARACTER_COMMIT_SHA"
curl -fsSLo bootstrap.sh "https://raw.githubusercontent.com/Akxios/3x-ui-setup/${SHA}/bootstrap.sh"
# Проверьте скачанный bootstrap.sh перед запуском от root.
sudo env REPO_COMMIT="$SHA" bash bootstrap.sh
```

В этом режиме bootstrap закрепит checkout в `/opt/3x-ui-setup` за выбранным коммитом. Для уже заполненного `/opt/3x-ui-setup/.env` можно запустить без вопросов:

```bash
sudo env REPO_COMMIT="$SHA" ASSUME_YES=true bash bootstrap.sh install
```

### Локальный клон

```bash
git clone https://github.com/Akxios/3x-ui-setup.git
cd 3x-ui-setup
cp .env.example .env
nano .env
sudo bash scripts/install.sh all
```

В `.env` обязательно замените `DOMAIN` и `LETSENCRYPT_EMAIL` на реальные значения. Файл читается как данные, без выполнения Bash. Остальные настройки можно оставить по умолчанию.

## 3. Что выполняет установка

| Шаг | Результат |
| --- | --- |
| Пакеты | Базовые утилиты для сервера и последующих шагов |
| UFW | Защита входящих подключений, сохранение SSH-доступа, разрешение нужных портов |
| Nginx и Certbot | Сайт в `WEB_ROOT`, конфиг в `sites-available`, сертификат и HTTPS |
| Fail2Ban | Отдельный jail проекта для SSH и nginx botsearch |
| 3x-ui | Установка закреплённой версии официальным installer и настройка через API |
| Проверка | Проверка панели и маршрута подписки через локальный HTTPS |

Команда `sudo bash scripts/install.sh all` выполняет эти шаги по порядку. Нужный модуль можно повторить отдельно: `packages`, `firewall`, `nginx`, `fail2ban`, `3x-ui` или `status`.

## 4. Адреса и порты после установки

| Сервис | Публичный доступ | Локальный сервис |
| --- | --- | --- |
| Сайт | `https://DOMAIN/` | Файлы `WEB_ROOT` |
| Панель | `https://DOMAIN/<случайный-путь>/` | `127.0.0.1:2053` |
| Подписки | Три ссылки со случайными путями для обычного, JSON и Clash форматов | `127.0.0.1:2096` |

Nginx использует публичный `443/tcp` для сайта, панели и подписок. Локальные порты панели и подписок не открываются наружу. Порт `8443/tcp` по умолчанию разрешён для будущего Xray inbound, но сам inbound и клиентов установщик не создаёт. Их нужно добавить в панели; фактические новые порты inbound затем указать в `XRAY_TCP_PORTS`/`XRAY_UDP_PORTS` и повторить модуль `firewall`.

После успешной проверки выводится карточка с адресами, логином, паролем и шаблонами ссылок. Повторно показать её можно командой:

```bash
sudo bash scripts/install.sh access
```

Данные хранятся в `/etc/3x-ui-setup/access.json`, карточка — в `/root/3x-ui-access.txt` с правами `600`. Пути и реквизиты сохраняются при повторном запуске. Для действительной персональной подписки сначала создайте inbound и клиента. Проверка установки подтверждает маршрут до сервиса подписок, но не содержимое клиентской ссылки.

## 5. Сайт и сертификат

Главная страница показывает домен и простую игру с племенем. Прогресс хранится в `localStorage` браузера; скрипт страницы не отправляет игровые данные на сервер. Установщик обновляет только страницу с маркером проекта, не заменяя пользовательский `index.html`.

При автоматическом HTTPS Certbot получает сертификат через webroot. Nginx сохраняет HTTP-маршрут `/.well-known/acme-challenge/` для проверки домена и перенаправляет обычные HTTP-запросы на HTTPS. Если сертификат уже существует, используйте `NGINX_USE_HTTPS=true`, `NGINX_AUTO_HTTPS=false` и задайте пути к файлам в [справочнике](configuration.md#nginx-и-tls).

TLS панели завершается на nginx; 3x-ui слушает локальный HTTP. Для Xray inbound с TLS можно использовать выпущенные файлы `/etc/letsencrypt/live/DOMAIN/fullchain.pem` и `privkey.pem`. При проблемах с выпуском смотрите [диагностику сертификата](operations.md#сертификат-lets-encrypt).
