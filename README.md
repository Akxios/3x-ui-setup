# 🚀 3x-ui setup

Быстрая и безопасная базовая настройка VPS-сервера с автоматической конфигурацией ключевых сервисов.

---

## ⚡ Быстрый старт

### 1) Bootstrap (рекомендуется)
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Akxios/3x-ui-setup/main/bootstrap.sh)
```
### 2) Альтернатива: официальный установщик [3x-ui](https://github.com/MHSanaei/3x-ui)
```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

---

## 🛠 Что настраивается
- 🌐 Nginx (редирект HTTP → HTTPS + заглушка)
- 🔥 UFW Firewall
- 🛡 Fail2Ban
- 📡 3x-ui (через официальный installer)
- 🚪 Порты для 3x-ui / Xray

## 🚫 Что НЕ изменяется

> ⚠️ Важно: безопасность SSH остаётся под вашим контролем.

- SSH-ключи
- SSH-порт

> 👉 SSH настраивается вручную.

## ⚙️ Базовый сценарий (по умолчанию)

Минимальная настройка через `.env`:
```bash
DOMAIN=example.com
LETSENCRYPT_EMAIL=your@email.com
```

- В firewall по умолчанию открываются `443/tcp` и `8443/tcp`.
- Порты панели 3x-ui по умолчанию не открываются — открывайте вручную при необходимости.

---

## 📄 Лицензия
Проект распространяется под лицензией MIT.
