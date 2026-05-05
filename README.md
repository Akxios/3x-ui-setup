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
