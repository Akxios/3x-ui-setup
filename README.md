# 🚀 3x-ui setup

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-blue)
![License](https://img.shields.io/badge/License-MIT-green)

`3x-ui setup` — набор Bash-скриптов для базовой подготовки собственного VPS-сервера. Проект автоматизирует установку и настройку системных компонентов, которые обычно нужны перед запуском 3x-ui/Xray: nginx, TLS-сертификат, firewall, Fail2Ban, базовые пакеты и сам 3x-ui через официальный installer.

Проект рассчитан на Debian/Ubuntu-подобные системы с `apt-get` и запускается от `root`.

---

## ⚠️ Назначение проекта и дисклеймер

Проект является техническим инструментом для автоматизации базовой настройки собственного VPS-сервера и носит ознакомительный, исследовательский и некоммерческий характер. Автор не призывает использовать проект для обхода блокировок, нарушения правил платформ или любых незаконных действий.

Полный текст: [DISCLAIMER.md](DISCLAIMER.md).

---

## Что делает проект

- Устанавливает базовые пакеты: `curl`, `wget`, `ca-certificates`, `gnupg`, `lsb-release`.
- Настраивает nginx-заглушку для домена.
- Может автоматически выпустить TLS-сертификат Let's Encrypt через Certbot.
- Настраивает UFW и открывает нужные TCP/UDP-порты.
- Настраивает Fail2Ban для SSH и, при необходимости, nginx botsearch.
- Устанавливает 3x-ui через официальный installer проекта [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui).
- Сохраняет итог установки и подробные логи.
- Даёт команды для статуса и управляемого удаления компонентов.

## Что проект не делает

> Безопасность SSH остаётся под вашим контролем.

- Не меняет SSH-ключи.
- Не меняет SSH-порт.
- Не отключает root-login.
- Не настраивает DNS у регистратора или провайдера.
- Не управляет пользователями, инбаундами и правилами внутри панели 3x-ui.
- Не выпускает сертификат внутри 3x-ui: сертификатом управляет nginx/Certbot.

## Требования

- Чистый или контролируемый VPS на Debian/Ubuntu.
- Root-доступ или пользователь с `sudo`.
- Домен, A/AAAA-запись которого уже указывает на IP сервера.
- Открытый доступ к портам `80/tcp` и `443/tcp` для Certbot и nginx.
- Доступ к GitHub, репозиториям apt и Let's Encrypt.
- Резервный способ входа на сервер через панель провайдера или rescue mode.

Перед запуском проверьте текущий SSH-порт и firewall-правила. Если UFW уже используется вручную, внимательно настройте `CURRENT_SSH_PORTS`, `UFW_RESET_RULES` и дополнительные порты в `.env`.

## Быстрый старт

### 1) Bootstrap с меню

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh)
```

Bootstrap скачает репозиторий в `/opt/3x-ui-setup`, создаст `.env` из `.env.example`, откроет меню и предложит минимальную настройку.

Меню bootstrap:

```text
1) Установить / обновить сервер
2) Открыть .env
3) Удалить сервисы
4) Показать статус
0) Выход
```

### 2) Установка без меню

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) install
```

### 3) Локальный запуск из клона

```bash
git clone https://github.com/Akxios/3x-ui-setup.git
cd 3x-ui-setup
cp .env.example .env
nano .env
sudo bash scripts/install.sh all
```

Минимально нужно заменить:

```bash
DOMAIN="example.com"
LETSENCRYPT_EMAIL="admin@example.com"
```

Полный справочник настроек: [docs/configuration.md](docs/configuration.md).

## Как проходит установка

Команда `sudo bash scripts/install.sh all` выполняет модули в таком порядке:

1. `packages` — установка базовых apt-пакетов.
2. `firewall` — настройка UFW, SSH-портов и портов web/3x-ui/Xray.
3. `nginx` — web-root, nginx-конфиг, проверка nginx, выпуск сертификата Certbot.
4. `fail2ban` — установка и настройка `/etc/fail2ban/jail.local`.
5. `3x-ui` — запуск официального installer, если `INSTALL_3X_UI=true`.
6. `status` — краткая проверка UFW и сервисов.

Каждый модуль можно запускать отдельно:

```bash
sudo bash scripts/install.sh packages
sudo bash scripts/install.sh firewall
sudo bash scripts/install.sh nginx
sudo bash scripts/install.sh fail2ban
sudo bash scripts/install.sh 3x-ui
sudo bash scripts/install.sh status
```

## Порты по умолчанию

- `80/tcp`, `443/tcp` — web/nginx и Certbot.
- `8443/tcp` — Xray/3x-ui порт из `XRAY_TCP_PORTS`.
- SSH-порт определяется автоматически через `sshd -T`; если определить не удалось, используется `22`.
- Порт панели 3x-ui по умолчанию не открывается. Если нужен внешний доступ к панели, укажите его явно в `XUI_PANEL_TCP_PORTS`.

Дополнительные порты задаются через:

```bash
EXTRA_TCP_PORTS="1234 5678"
EXTRA_UDP_PORTS="1234"
```

## Сертификаты и 3x-ui

Nginx выпускает сертификат через Certbot. Не выпускайте второй сертификат внутри 3x-ui для того же домена без необходимости.

В панели 3x-ui используйте существующие пути:

```bash
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
```

Если у вас уже есть сертификат, отключите автоматический выпуск и укажите пути вручную:

```bash
NGINX_AUTO_HTTPS="false"
NGINX_USE_HTTPS="true"
NGINX_CERT_PATH="/path/to/fullchain.pem"
NGINX_CERT_KEY_PATH="/path/to/privkey.pem"
```

## Логи и итог установки

По умолчанию:

- итог установки сохраняется в `/root/vps-bootstrap-summary.txt`;
- подробные логи сохраняются в `/var/log/vps-bootstrap/`;
- transcript официального installer 3x-ui сохраняется отдельным файлом в `LOG_DIR`;
- команды `status` и `remove` пишут временные summary в `LOG_DIR`, чтобы не перезаписать итог установки.

При `VERBOSE=false` установщик показывает только ключевые шаги и последние строки лога при ошибке. При `VERBOSE=true` вывод apt, ufw, systemctl, nginx и certbot будет подробным.

## Удаление

Интерактивное удаление через bootstrap:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh) remove
```

Локально после установки:

```bash
sudo bash scripts/install.sh remove
sudo bash scripts/install.sh remove nginx
sudo bash scripts/install.sh remove fail2ban
sudo bash scripts/install.sh remove 3x-ui
sudo bash scripts/install.sh remove ufw
sudo bash scripts/install.sh remove all
```

По умолчанию удаляются управляемые конфиги/сервисы, но web-root, certbot-сертификаты, данные 3x-ui и apt-пакеты сохраняются.

Для более жёсткого удаления включите нужные флаги в `.env`:

```bash
REMOVE_WEB_ROOT="true"
REMOVE_CERTBOT_CERT="true"
REMOVE_FAIL2BAN_JAIL="true"
REMOVE_XUI_DATA="true"
PURGE_PACKAGES="true"
```

`REMOVE_CONFIRM=true` отключает интерактивные подтверждения. Используйте этот флаг только когда точно понимаете последствия.

## Диагностика

Проверить краткий статус:

```bash
sudo bash scripts/install.sh status
```

Получить более подробный статус:

```bash
sudo bash scripts/install.sh status
```

Для подробного вывода установите `VERBOSE="true"` в `.env` перед запуском `status`.

Типовые места для проверки:

- `/root/vps-bootstrap-summary.txt` — итог установки, домен, лог, найденные данные installer.
- `/var/log/vps-bootstrap/` — подробные логи команд.
- `systemctl status nginx --no-pager -l` — состояние nginx.
- `nginx -t` — проверка nginx-конфига.
- `ufw status verbose` — firewall-правила.
- `fail2ban-client status` — состояние Fail2Ban.
- `systemctl status x-ui --no-pager -l` — состояние 3x-ui.

## Структура проекта

```text
bootstrap.sh                 # удалённый bootstrap, меню и подготовка репозитория
scripts/install.sh           # главный оркестратор локальной установки
scripts/lib/                 # общие функции, проверки, шаблонизатор
scripts/modules/             # отдельные модули установки, статуса и удаления
templates/                   # nginx, fail2ban и web-заглушка
docs/configuration.md        # полный справочник .env
DISCLAIMER.md                # назначение проекта и дисклеймер
```

## Лицензия

Проект распространяется под лицензией MIT. См. [LICENSE](LICENSE).
