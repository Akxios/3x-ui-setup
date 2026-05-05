```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh)
```


bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)



# VPS Bootstrap

Быстрая базовая настройка VPS.

## Что настраивает

- nginx-заглушку
- UFW firewall
- Fail2Ban
- 3x-ui через официальный installer
- порты для 3x-ui / Xray

## Что НЕ трогает

- SSH-ключи
- SSH-порт
- PasswordAuthentication
- PermitRootLogin

SSH пользователь настраивает сам.

## Установка

```bash
cp .env.example .env
nano .env
sudo bash scripts/install.sh all


## Базовый сценарий (по умолчанию)

- В `.env` достаточно указать `DOMAIN` и `LETSENCRYPT_EMAIL`.
- Скрипт сам поднимет HTTP-заглушку, выпустит Let's Encrypt сертификат и переключит nginx на HTTPS.
- Если выпуск сертификата не удался (DNS/ACME), скрипт не падает: оставляет рабочий HTTP и выводит предупреждение.
- В режиме `all` firewall настраивается до шага nginx, чтобы `80/tcp` был открыт для ACME HTTP-01 challenge.
- В firewall по умолчанию открываются `443/tcp` и `8443/tcp`.
- Порты панели 3x-ui по умолчанию не открываются — открывайте вручную при необходимости.
