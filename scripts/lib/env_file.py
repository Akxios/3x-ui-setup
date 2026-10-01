#!/usr/bin/env python3
"""Parse the supported .env subset as data and emit NUL-delimited pairs."""

import re
import shlex
import sys
from pathlib import Path

ALLOWED = set(
    """DOMAIN LETSENCRYPT_EMAIL ENABLE_WWW ENABLE_NGINX WEB_ROOT NGINX_AUTO_HTTPS
    NGINX_USE_HTTPS NGINX_CERT_PATH NGINX_CERT_KEY_PATH ENABLE_UFW
    UFW_DEFAULT_INCOMING UFW_DEFAULT_OUTGOING UFW_RESET_RULES CURRENT_SSH_PORTS
    LIMIT_SSH_PORT WEB_TCP_PORTS WEB_UDP_PORTS ENABLE_3X_UI_PORTS XRAY_TCP_PORTS
    XRAY_UDP_PORTS XUI_PANEL_TCP_PORTS EXTRA_TCP_PORTS EXTRA_UDP_PORTS ENABLE_FAIL2BAN
    FAIL2BAN_BANTIME FAIL2BAN_FINDTIME FAIL2BAN_MAXRETRY FAIL2BAN_BANACTION
    FAIL2BAN_IGNORE_IPS ENABLE_NGINX_BOTSEARCH INSTALL_3X_UI THREE_X_UI_VERSION
    THREE_X_UI_INSTALL_URL THREE_X_UI_INSTALL_SHA256 XUI_INSTALL_VISIBLE
    XUI_AUTO_CONFIGURE XUI_STATE_FILE XUI_ACCESS_FILE XUI_PANEL_PORT XUI_SUB_PORT
    XUI_USERNAME XUI_PASSWORD XUI_WEB_BASE_PATH REMOVE_WEB_ROOT REMOVE_CERTBOT_CERT
    REMOVE_XUI_DATA PURGE_PACKAGES REMOVE_CONFIRM VERBOSE LOG_DIR SUMMARY_FILE""".split()
)
DOMAIN_TOKEN_FIELDS = {"WEB_ROOT", "NGINX_CERT_PATH", "NGINX_CERT_KEY_PATH"}
ASSIGNMENT = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$")
DOMAIN = re.compile(
    r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"
)


def parse(path):
    if path.stat().st_size > 65536:
        raise ValueError(".env слишком большой (максимум 64 КиБ)")
    values = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = ASSIGNMENT.fullmatch(line)
        if not match:
            raise ValueError(f"строка {number}: ожидалось KEY=VALUE без команд Bash")
        name, raw = match.groups()
        if name not in ALLOWED:
            raise ValueError(f"строка {number}: неизвестная настройка {name}")
        if name in values:
            raise ValueError(f"строка {number}: повторная настройка {name}")
        lexer = shlex.shlex(raw, posix=True)
        lexer.whitespace_split = True
        lexer.commenters = "#"
        try:
            parts = list(lexer)
        except ValueError as error:
            raise ValueError(
                f"строка {number}: незакрытая кавычка или escape"
            ) from error
        if len(parts) > 1:
            raise ValueError(
                f"строка {number}: значение должно быть одним словом или в кавычках"
            )
        value = parts[0] if parts else ""
        if "\x00" in value or "\r" in value or "\n" in value or len(value) > 4096:
            raise ValueError(f"строка {number}: некорректная длина или символ в {name}")
        values[name] = value

    domain = values.get("DOMAIN", "")
    if domain and not DOMAIN.fullmatch(domain):
        raise ValueError("DOMAIN должен быть корректным доменным именем")
    for name in DOMAIN_TOKEN_FIELDS & values.keys():
        values[name] = values[name].replace("${DOMAIN}", domain)
    return values


def main():
    try:
        values = parse(Path(sys.argv[1]))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Ошибка .env: {error}", file=sys.stderr)
        return 1
    for name, value in values.items():
        sys.stdout.buffer.write(name.encode() + b"\0" + value.encode() + b"\0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
