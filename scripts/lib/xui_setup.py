#!/usr/bin/env python3
"""3x-ui provisioning via its authenticated API; no direct database writes."""

import http.cookiejar
import json
import os
import re
import secrets
import shlex
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


class SetupError(Exception):
    pass


def atomic_write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def state_path():
    return Path(os.environ.get("XUI_STATE_FILE", "/etc/3x-ui-setup/access.json"))


def pending_state_path():
    path = state_path()
    return path.with_name(path.name + ".pending")


def load_state():
    return json.loads(state_path().read_text())


def load_pending_state():
    return json.loads(pending_state_path().read_text())


def save_state(state):
    atomic_write(state_path(), json.dumps(state, ensure_ascii=False, indent=2) + "\n")


def save_pending_state(state):
    atomic_write(
        pending_state_path(), json.dumps(state, ensure_ascii=False, indent=2) + "\n"
    )


def discard_pending(force=False):
    if not force:
        if not state_path().exists() or not pending_state_path().exists():
            return
        if load_pending_state().get("service_changed"):
            raise SetupError(
                "Откат 3x-ui не подтверждён; промежуточное состояние сохранено"
            )
    pending_state_path().unlink(missing_ok=True)


def port(value):
    if not str(value).isdigit() or not 1 <= int(value) <= 65535:
        raise SetupError("Порт должен быть числом от 1 до 65535")
    return int(value)


def base_path(value):
    value = "/" + value.strip("/") + "/"
    if not re.fullmatch(r"/[A-Za-z0-9_-]{4,80}/", value):
        raise SetupError("Путь панели: 4–80 букв, цифр, _ или -")
    if value in ("/sub/", "/subjson/", "/subclash/"):
        raise SetupError("Путь панели совпадает с путём подписок")
    return value


def existing_path(value):
    return "/" + value.strip("/") + "/" if value.strip("/") else "/"


def subscription_path(value):
    if not isinstance(value, str):
        raise SetupError("Путь подписки должен быть строкой")
    value = existing_path(value)
    if not re.fullmatch(r"/[A-Za-z0-9_-]{1,80}/", value):
        raise SetupError("Путь подписки содержит недопустимые символы")
    return value


def subscription_paths(state):
    return (
        subscription_path(state.get("sub_path", "/sub/")),
        subscription_path(state.get("sub_json_path", "/subjson/")),
        subscription_path(state.get("sub_clash_path", "/subclash/")),
    )


def installed():
    return Path("/usr/local/x-ui/x-ui").is_file()


def current_endpoint():
    binary = "/usr/local/x-ui/x-ui"
    output = subprocess.check_output([binary, "setting", "-show"], text=True)
    match_port = re.search(r"^port:\s*(\d+)\s*$", output, re.M)
    match_path = re.search(r"^webBasePath:\s*(\S+)\s*$", output, re.M)
    if not match_port or not match_path:
        raise SetupError("Не удалось прочитать текущий порт и путь 3x-ui")
    cert = subprocess.check_output([binary, "setting", "-getCert"], text=True)
    # Only horizontal whitespace is allowed after cert:. \s also consumes the
    # newline and mistakes the following key: line for a certificate value.
    scheme = "https" if re.search(r"^cert:[ \t]*\S+", cert, re.M) else "http"
    return f"{scheme}://127.0.0.1:{port(match_port[1])}" + existing_path(match_path[1])


class Panel:
    def __init__(self, url, username, password, host=None):
        self.url = url
        jar = http.cookiejar.CookieJar()
        context = ssl.create_default_context()
        # Local connection only: validate the certificate chain, not 127.0.0.1.
        context.check_hostname = False
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            urllib.request.HTTPCookieProcessor(jar),
            urllib.request.HTTPSHandler(context=context),
        )
        self.headers = {"Content-Type": "application/json"}
        if host:
            self.headers["Host"] = host
        self.csrf()
        self.request("login", {"username": username, "password": password})
        self.csrf()  # Login may rotate the session/token.
        self.route = "panel/api/setting/"

    def request(self, route, data=None):
        request = urllib.request.Request(
            self.url + route,
            data=None if data is None else json.dumps(data).encode(),
            headers=self.headers,
        )
        with self.opener.open(request, timeout=15) as response:
            result = json.load(response)
        if not isinstance(result, dict) or result.get("success") is not True:
            # Don't echo arbitrary API messages: they can contain credentials.
            raise SetupError(
                "API отклонил запрос " + route + ". Проверьте реквизиты и 2FA."
            )
        return result.get("obj")

    def csrf(self):
        try:
            token = self.request("csrf-token")
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            return  # Older panels have no CSRF endpoint.
        if not isinstance(token, str) or not token:
            raise SetupError("API вернул некорректный CSRF token")
        self.headers["X-CSRF-Token"] = token

    def settings(self):
        try:
            result = self.request(self.route + "all", {})
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            self.route = "panel/setting/"
            result = self.request(self.route + "all", {})
        if (
            not isinstance(result, dict)
            or "webPort" not in result
            or "subPort" not in result
        ):
            raise SetupError("Неподдерживаемый ответ API настроек")
        return result


def desired_settings(state):
    domain = state["domain"]
    sub_path, json_path, clash_path = subscription_paths(state)
    return {
        "webListen": "127.0.0.1",
        "webPort": state["panel_port"],
        "webBasePath": state["panel_path"],
        "webDomain": domain,
        "webCertFile": "",
        "webKeyFile": "",
        "subEnable": True,
        "subListen": "127.0.0.1",
        "subPort": state["sub_port"],
        "subDomain": domain,
        "subPath": sub_path,
        "subCertFile": "",
        "subKeyFile": "",
        "subURI": f"https://{domain}{sub_path}",
        "subJsonPath": json_path,
        "subJsonEnable": True,
        "subJsonURI": f"https://{domain}{json_path}",
        "subClashPath": clash_path,
        "subClashEnable": True,
        "subClashURI": f"https://{domain}{clash_path}",
    }


def check_ports(state, settings=None):
    owned = set()
    if settings:
        owned.add(int(settings["webPort"]))
        if settings.get("subEnable"):
            owned.add(int(settings["subPort"]))
    for number in (state["panel_port"], state["sub_port"]):
        if number in owned:
            continue
        with socket.socket() as sock:
            try:
                sock.bind(("127.0.0.1", number))
            except OSError:
                raise SetupError(
                    f"Порт {number} занят. Укажите другой порт в .env"
                ) from None


def import_result():
    result = {}
    path = Path("/etc/x-ui/install-result.env")
    if path.is_file():
        # Parse data, never execute the shell file. Unsupported shell quoting
        # requires explicit credentials in .env.
        for line in path.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key in ("XUI_USERNAME", "XUI_PASSWORD"):
                parts = shlex.split(value)
                if len(parts) == 1 and not value.startswith("$'"):
                    result[key] = parts[0]
    return result


def prepare():
    domain = os.environ["DOMAIN"]
    if not re.fullmatch(r"[A-Za-z0-9.-]+", domain):
        raise SetupError("Некорректный домен")
    active = load_state() if state_path().exists() else {}
    state = (
        active.copy()
        if active
        else (load_pending_state() if pending_state_path().exists() else {})
    )
    previously_verified = active.get("verified") is True
    if state and state["domain"] != domain:
        raise SetupError(
            "DOMAIN отличается от сохранённого. Миграцию домена выполните отдельно."
        )
    has_panel = installed()
    imported = import_result() if has_panel else {}
    username = (
        os.environ.get("XUI_USERNAME")
        or state.get("username")
        or imported.get("XUI_USERNAME")
    )
    password = (
        os.environ.get("XUI_PASSWORD")
        or state.get("password")
        or imported.get("XUI_PASSWORD")
    )
    if has_panel and not (username and password):
        raise SetupError(
            "Панель уже установлена. Укажите её текущие XUI_USERNAME и XUI_PASSWORD в .env. Пароль не сбрасывался."
        )
    state.update(
        {
            "domain": domain,
            "username": username or ("user_" + secrets.token_hex(4)),
            "password": password or secrets.token_urlsafe(24),
            "panel_port": port(
                os.environ.get("XUI_PANEL_PORT") or state.get("panel_port", 2053)
            ),
            "sub_port": port(
                os.environ.get("XUI_SUB_PORT") or state.get("sub_port", 2096)
            ),
            "panel_path": base_path(
                os.environ.get("XUI_WEB_BASE_PATH")
                or state.get("panel_path")
                or secrets.token_hex(12)
            ),
            "verified": False,
        }
    )
    if state["panel_port"] == state["sub_port"] or {
        state["panel_port"],
        state["sub_port"],
    } & {80, 443}:
        raise SetupError(
            "Порты панели и подписки должны различаться и не занимать 80/443"
        )
    reserved = set()
    for name in ("XRAY_TCP_PORTS", "EXTRA_TCP_PORTS", "CURRENT_SSH_PORTS"):
        reserved.update(int(p) for p in os.environ.get(name, "").split() if p.isdigit())
    if reserved & {state["panel_port"], state["sub_port"]}:
        raise SetupError(
            "Порт панели/подписки совпадает с SSH, Xray или EXTRA_TCP_PORTS"
        )
    settings = None
    if has_panel:
        api = Panel(current_endpoint(), username, password, domain)
        settings = api.settings()  # Authenticate before changing anything.
    for state_key, api_key in (
        ("sub_path", "subPath"),
        ("sub_json_path", "subJsonPath"),
        ("sub_clash_path", "subClashPath"),
    ):
        current = (settings or {}).get(api_key)
        value = (
            (current if previously_verified else None)
            or state.get(state_key)
            or current
        )
        state[state_key] = subscription_path(value or secrets.token_hex(12))
    if len({state["panel_path"], *subscription_paths(state)}) != 4:
        raise SetupError("Пути панели и подписок должны различаться")
    check_ports(state, settings)
    save_pending_state(state)  # Persist generated credentials BEFORE installer starts.


def run_installer(filename, version):
    state = load_pending_state()
    env = os.environ.copy()
    env.update(
        XUI_NONINTERACTIVE="1",
        XUI_SSL_MODE="none",
        XUI_DB_TYPE="sqlite",
        XUI_ENABLE_FAIL2BAN="false",
        XUI_USERNAME=state["username"],
        XUI_PASSWORD=state["password"],
        XUI_PANEL_PORT=str(state["panel_port"]),
        XUI_WEB_BASE_PATH=state["panel_path"].strip("/"),
    )
    subprocess.run(["bash", filename, version], env=env, check=True)


def wait_panel(state, url=None):
    url = url or f"http://127.0.0.1:{state['panel_port']}{state['panel_path']}"
    context = ssl.create_default_context()
    context.check_hostname = False
    opener = urllib.request.build_opener(
        urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=context)
    )
    last_error = None
    for _ in range(30):
        try:
            with opener.open(
                urllib.request.Request(url, headers={"Host": state["domain"]}),
                timeout=2,
            ):
                return url
        except urllib.error.HTTPError as error:
            last_error = f"HTTP {error.code}"
            if error.code in (401, 403, 404):
                break
            time.sleep(1)
        except (OSError, urllib.error.URLError) as error:
            last_error = type(error).__name__
            time.sleep(1)
    raise SetupError(
        "Панель не ответила по локальному адресу за отведённое время"
        + (f" (последняя ошибка: {last_error})" if last_error else "")
        + "; проверьте systemctl status x-ui и journalctl -u x-ui"
    )


def configure():
    state = load_pending_state()
    endpoint = wait_panel(state, current_endpoint())
    api = Panel(endpoint, state["username"], state["password"], state["domain"])
    settings = api.settings()
    missing = [
        key for key in ("subJsonEnable", "subClashEnable") if key not in settings
    ]
    if missing:
        raise SetupError(
            "Эта версия 3x-ui не поддерживает обязательные форматы подписки: "
            + ", ".join(missing)
            + ". Используйте поддерживаемую версию 3x-ui."
        )
    check_ports(state, settings)
    atomic_write(
        state_path().parent / "settings-before.json", json.dumps(settings, indent=2)
    )
    desired = desired_settings(state)
    changed = any(settings.get(key) != value for key, value in desired.items())
    if "trustedProxyCIDRs" in settings:
        changed = changed or settings["trustedProxyCIDRs"] != "127.0.0.1/32,::1/128"
    # Preserve all unrelated settings, including flags used to retain redacted secrets.
    settings.update(desired)
    if "trustedProxyCIDRs" in settings:
        settings["trustedProxyCIDRs"] = "127.0.0.1/32,::1/128"
    state["service_changed"] = changed
    save_pending_state(state)
    if not changed:
        return
    attempted = False
    try:
        attempted = True
        api.request(api.route + "update", settings)
        subprocess.run(["systemctl", "restart", "x-ui"], check=True)
        url = wait_panel(state)
        api = Panel(url, state["username"], state["password"], state["domain"])
        actual = api.settings()
        for key, value in desired.items():
            if actual.get(key) != value:
                raise SetupError("Настройка не применена: " + key)
    except Exception:
        if attempted:
            try:
                rollback()
            except Exception:
                print(
                    "Откат настроек 3x-ui не удался; проверьте settings-before.json",
                    file=sys.stderr,
                )
        raise


def rollback():
    state = load_pending_state()
    if not state.get("service_changed"):
        return
    before = json.loads((state_path().parent / "settings-before.json").read_text())
    candidates = [
        f"http://127.0.0.1:{state['panel_port']}{state['panel_path']}",
        f"http://127.0.0.1:{port(before['webPort'])}"
        + existing_path(before.get("webBasePath", "/")),
    ]
    if before.get("webCertFile") and before.get("webKeyFile"):
        candidates.append(candidates[-1].replace("http://", "https://", 1))
    last_error = None
    for candidate in candidates:
        try:
            api = Panel(
                candidate, state["username"], state["password"], state["domain"]
            )
            api.settings()
            api.request(api.route + "update", before)
            subprocess.run(["systemctl", "restart", "x-ui"], check=True)
            state["service_changed"] = False
            save_pending_state(state)
            return
        except (
            OSError,
            ValueError,
            SetupError,
            subprocess.SubprocessError,
            urllib.error.URLError,
        ) as error:
            last_error = error
    raise SetupError("Не удалось восстановить настройки 3x-ui") from last_error


def proxy():
    state = (
        load_pending_state()
        if os.environ.get("XUI_PROXY_PENDING") == "true"
        else load_state()
    )
    if state["domain"] != os.environ["DOMAIN"]:
        raise SetupError("Домен сохранённой панели не совпадает с DOMAIN")
    panel_path = base_path(state["panel_path"])
    sub_path, json_path, clash_path = subscription_paths(state)
    for path, number in (
        (panel_path, port(state["panel_port"])),
        (sub_path, port(state["sub_port"])),
        (json_path, port(state["sub_port"])),
        (clash_path, port(state["sub_port"])),
    ):
        route = "panel" if path == panel_path else "subscription"
        print(f"""    location ^~ {path} {{
        proxy_pass http://127.0.0.1:{number};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300s;
        proxy_buffering off;
        add_header X-3x-UI-Route {route} always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-Frame-Options DENY always;
        add_header Referrer-Policy no-referrer-when-downgrade always;
        add_header Strict-Transport-Security "max-age=31536000" always;
    }}""")


def verify():
    state = load_pending_state()
    domain = state["domain"]
    sub_path, json_path, clash_path = subscription_paths(state)
    # --resolve exercises nginx routing and real TLS verification locally.
    # This cannot prove that a provider firewall permits external connections.
    for path, route in (
        (state["panel_path"], "panel"),
        (sub_path + "__setup_healthcheck__", "subscription"),
        (json_path + "__setup_healthcheck__", "subscription"),
        (clash_path + "__setup_healthcheck__", "subscription"),
    ):
        result = subprocess.run(
            [
                "curl",
                "--noproxy",
                "*",
                "--silent",
                "--show-error",
                "--max-time",
                "15",
                "--resolve",
                f"{domain}:443:127.0.0.1",
                "-D",
                "-",
                "-o",
                "/dev/null",
                f"https://{domain}{path}",
            ],
            capture_output=True,
            text=True,
        )
        headers = result.stdout.lower()
        match = re.search(r"^http/\S+\s+(\d{3})", headers, re.M)
        acceptable = {"200"} if route == "panel" else {"200", "400", "404"}
        if (
            result.returncode
            or not match
            or match[1] not in acceptable
            or f"x-3x-ui-route: {route}" not in headers
        ):
            raise SetupError("Не прошла проверка HTTPS панели/подписки через nginx")
    with socket.create_connection(("127.0.0.1", state["sub_port"]), timeout=5):
        pass
    state["verified"] = True
    state.pop("service_changed", None)
    card_path = Path(os.environ.get("XUI_ACCESS_FILE", "/root/3x-ui-access.txt"))
    if card_path.is_symlink():
        raise SetupError("Файл карточки доступа не должен быть символьной ссылкой")
    previous_card = card_path.read_text() if card_path.exists() else None
    atomic_write(card_path, access_text(state))
    try:
        save_state(state)
    except Exception:
        if previous_card is None:
            card_path.unlink(missing_ok=True)
        else:
            atomic_write(card_path, previous_card)
        raise
    discard_pending(force=True)


def access_text(state):
    verified = state.get("verified", False)
    title = "УСТАНОВКА ЗАВЕРШЕНА" if verified else "НАСТРОЙКА НЕ ЗАВЕРШЕНА"
    sub_path, json_path, clash_path = subscription_paths(state)
    rows = [
        ("Сайт", f"https://{state['domain']}/"),
        ("Панель", f"https://{state['domain']}{state['panel_path']}"),
        ("Логин", state["username"]),
        ("Пароль", state["password"]),
        ("Подписка (шаблон)", f"https://{state['domain']}{sub_path}<ID-клиента>"),
        ("JSON (шаблон)", f"https://{state['domain']}{json_path}<ID-клиента>"),
        ("Clash (шаблон)", f"https://{state['domain']}{clash_path}<ID-клиента>"),
        ("Внешний HTTPS-порт", "443/tcp — сайт, панель и подписка"),
        ("Панель на сервере", f"127.0.0.1:{state['panel_port']}"),
        ("Подписка на сервере", f"127.0.0.1:{state['sub_port']}"),
        (
            "Файл доступа",
            os.environ.get("XUI_ACCESS_FILE", "/root/3x-ui-access.txt"),
        ),
    ]
    label_width = max(len(label) for label, _ in rows)
    lines = [f"{label.ljust(label_width)}  {value}" for label, value in rows]
    note = (
        "Проверка HTTPS-маршрутов и входа пройдена; клиентская подписка не проверена."
        if verified
        else "Проверка не завершена; доступность сервиса не подтверждена."
    )
    hints = [
        note,
        "Ссылку клиента получите после создания inbound и клиента в панели.",
        "После ручной смены пароля сохранённые реквизиты могут устареть.",
    ]
    width = max(
        len(title), *(len(line) for line in lines), *(len(hint) for hint in hints)
    )

    def framed(line):
        return f"│ {line.ljust(width)} │"

    border = "─" * (width + 2)
    return "\n".join(
        [
            "╭" + border + "╮",
            framed(title.center(width)),
            "├" + border + "┤",
            *(framed(line) for line in lines),
            "├" + border + "┤",
            *(framed(hint) for hint in hints),
            "╰" + border + "╯",
            "",
        ]
    )


def main():
    command = sys.argv[1]
    if command == "prepare":
        prepare()
    elif command == "install":
        run_installer(*sys.argv[2:])
    elif command == "configure":
        configure()
    elif command == "rollback":
        rollback()
    elif command == "proxy":
        proxy()
    elif command == "ports":
        state = load_pending_state() if pending_state_path().exists() else load_state()
        print(state["panel_port"], state["sub_port"])
    elif command == "verify":
        verify()
    elif command == "access":
        state = load_state() if state_path().exists() else load_pending_state()
        print(access_text(state), end="")
    elif command == "discard":
        discard_pending()
    elif command == "invalidate":
        discard_pending(force=True)
        if state_path().exists():
            state = load_state()
            state["verified"] = False
            save_state(state)
        Path(os.environ.get("XUI_ACCESS_FILE", "/root/3x-ui-access.txt")).unlink(
            missing_ok=True
        )
    else:
        raise SetupError("Неизвестная команда")


if __name__ == "__main__":
    try:
        main()
    except (
        SetupError,
        OSError,
        ValueError,
        subprocess.SubprocessError,
        urllib.error.URLError,
    ) as error:
        # HTTP and subprocess errors must not expose request bodies/environment.
        message = (
            str(error)
            if isinstance(error, SetupError)
            else (
                type(error).__name__
                + ": проверьте доступность API, сертификат и состояние x-ui"
            )
        )
        print("Ошибка настройки 3x-ui: " + message, file=sys.stderr)
        sys.exit(1)
