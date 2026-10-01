# 3x-ui setup

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-blue)
![License](https://img.shields.io/badge/License-MIT-green)

Автоматическая подготовка Debian/Ubuntu VPS: nginx, HTTPS через Certbot, UFW, Fail2Ban, сайт и 3x-ui. Установщик создаёт nginx-сайт для домена и показывает закрытую карточку с адресом панели, путями подписок и учётными данными.

## ⚠️ Назначение проекта и дисклеймер

Проект является техническим инструментом для автоматизации базовой настройки собственного VPS-сервера и носит ознакомительный, исследовательский и некоммерческий характер. Автор не призывает использовать проект для обхода блокировок, нарушения правил платформ или любых незаконных действий.

Полный текст: [DISCLAIMER.md](DISCLAIMER.md).

| Руководство | Что в нём |
| --- | --- |
| [Установка](docs/installation.md) | Требования, bootstrap, локальный запуск, порядок установки и результат |
| [Настройки `.env`](docs/configuration.md) | Примеры и описание переменных по компонентам |
| [Эксплуатация](docs/operations.md) | Повторный запуск, доступ, логи, диагностика и удаление |
| [Безопасность](docs/security.md) | Границы автоматизации, защита сервера и проверка загрузок |

## Быстрый старт

Нужны root-доступ к VPS, домен с A/AAAA-записями на этот сервер и доступные извне `80/tcp` и `443/tcp`. Проверьте текущий SSH-порт перед включением UFW. Подробная подготовка — в [руководстве по установке](docs/installation.md).

Скачайте bootstrap из **проверенного коммита** и передайте тот же SHA для установки репозитория:

```bash
SHA="PASTE_40_CHARACTER_COMMIT_SHA"
curl -fsSLo bootstrap.sh "https://raw.githubusercontent.com/Akxios/3x-ui-setup/${SHA}/bootstrap.sh"
# Проверьте скачанный файл перед запуском от root.
sudo env REPO_COMMIT="$SHA" bash bootstrap.sh
```

Bootstrap установит базовые утилиты, создаст `/opt/3x-ui-setup/.env` и откроет меню настройки. Для самостоятельного локального запуска:

```bash
git clone https://github.com/Akxios/3x-ui-setup.git
cd 3x-ui-setup
cp .env.example .env
nano .env  # Укажите реальные DOMAIN и LETSENCRYPT_EMAIL.
sudo bash scripts/install.sh all
```

`.env` разбирается как данные, а не выполняется как Bash. Достаточно указать:

```dotenv
DOMAIN="vpn.example.org"
LETSENCRYPT_EMAIL="admin@example.org"
```

## Что получится

| Компонент | Внешний адрес или порт |
| --- | --- |
| Сайт | `https://DOMAIN/` |
| Панель 3x-ui | `https://DOMAIN/<случайный-путь>/` |
| Подписки | Три отдельные ссылки с сохранёнными путями для обычного, JSON и Clash форматов |
| Xray inbound | `8443/tcp` разрешён по умолчанию; inbound и клиента нужно создать в панели |

Сайт, панель и подписки используют публичный `443/tcp`; внутренние порты панели и подписок привязаны к `127.0.0.1`. Nginx завершает TLS и автоматически подключает файл из `sites-available` через `sites-enabled`. Реальные адреса и реквизиты после успешной проверки показывает карточка:

```bash
sudo bash scripts/install.sh access
```

Шаблон подписки станет рабочей персональной ссылкой после создания inbound и клиента. Проверка установки подтверждает маршрут до сервиса подписок, но не содержимое клиентской подписки. Игра на главной странице хранит прогресс только в `localStorage` браузера.

## Управление

```bash
sudo bash scripts/install.sh status
sudo bash scripts/install.sh nginx
sudo bash scripts/install.sh firewall
sudo bash scripts/install.sh remove
```

Скрипт не меняет настройки SSH, не настраивает DNS и не создаёт Xray inbound или клиентов. Повторный запуск и удаление описаны в [эксплуатации](docs/operations.md). Для проблем с сертификатом смотрите [диагностику ACME](docs/operations.md#сертификат-lets-encrypt).

Лицензия: [MIT](LICENSE).
