"""Read-only diagnostics for an installed 3x-ui-setup server."""

import ipaddress
import json
import os
import re
import subprocess
from pathlib import Path


def run_command(args, timeout=8, input_text=None):
    safe_env = {
        name: os.environ[name]
        for name in ("PATH", "HOME", "SSL_CERT_FILE", "SSL_CERT_DIR")
        if name in os.environ
    }
    safe_env["LC_ALL"] = "C"
    try:
        return subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            input=input_text,
            env=safe_env,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def valid_path(value, minimum=1):
    return (
        isinstance(value, str)
        and re.fullmatch(rf"/[A-Za-z0-9_-]{{{minimum},80}}/", value) is not None
    )


def load_routes(path, domain):
    """Return only non-secret routing fields from the protected state file."""
    file = Path(path)
    try:
        if file.is_symlink() or not file.is_file() or file.stat().st_size > 65536:
            return None
        state = json.loads(file.read_text(encoding="utf-8"))
        if not isinstance(state, dict) or state.get("domain") != domain:
            return None
        paths = (
            state.get("panel_path"),
            state.get("sub_path", "/sub/"),
            state.get("sub_json_path", "/subjson/"),
            state.get("sub_clash_path", "/subclash/"),
        )
        if not valid_path(paths[0], 4) or not all(valid_path(p) for p in paths[1:]):
            return None
        ports = (state.get("panel_port"), state.get("sub_port"))
        if any(not str(p).isdigit() or not 1 <= int(p) <= 65535 for p in ports):
            return None
        if int(ports[0]) == int(ports[1]):
            return None
        return paths, tuple(map(int, ports))
    except (OSError, UnicodeError, ValueError, TypeError):
        return None


def listening_only_locally(output, ports):
    found = {port: False for port in ports}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) < 4 or ":" not in fields[3]:
            continue
        host, port_text = fields[3].rsplit(":", 1)
        if not port_text.isdigit() or int(port_text) not in found:
            continue
        if host not in ("127.0.0.1", "[::1]", "::1"):
            return False
        found[int(port_text)] = True
    return all(found.values())


class Doctor:
    def __init__(self, config):
        self.config = config
        self.problems = 0
        self.warnings = 0

    def check(self, label, ok, action):
        if ok:
            print(f"✓ {label}")
        else:
            self.problems += 1
            print(f"✗ {label} — {action}")

    def warn(self, message):
        self.warnings += 1
        print(f"! {message}")

    def command_ok(self, args):
        result = run_command(args)
        return result is not None and result.returncode == 0

    def dns(self):
        names = [self.config["DOMAIN"]]
        if self.config["ENABLE_WWW"]:
            names.append("www." + names[0])
        for name in names:
            result = run_command(["getent", "ahosts", name], timeout=6)
            addresses = set()
            if result and result.returncode == 0:
                for line in result.stdout.splitlines():
                    try:
                        addresses.add(str(ipaddress.ip_address(line.split()[0])))
                    except (IndexError, ValueError):
                        continue
            self.check(
                f"DNS {name}"
                + (f": {', '.join(sorted(addresses)[:4])}" if addresses else ""),
                bool(addresses),
                "проверьте A/AAAA-записи домена",
            )

    def nginx(self):
        domain = self.config["DOMAIN"]
        available = Path(self.config["NGINX_SITE_DIR"]) / domain
        enabled = Path(self.config["NGINX_ENABLED_DIR"]) / domain
        self.check(
            "Служба nginx",
            self.command_ok(["systemctl", "is-active", "--quiet", "nginx"]),
            "проверьте systemctl status nginx",
        )
        self.check(
            "Синтаксис nginx", self.command_ok(["nginx", "-t"]), "запустите nginx -t"
        )
        result = run_command(["nginx", "-T"], timeout=10)
        try:
            loaded = (
                available.is_file()
                and not available.is_symlink()
                and enabled.is_symlink()
                and enabled.resolve() == available
                and result is not None
                and result.returncode == 0
                and (
                    f"# configuration file {enabled}:" in result.stdout
                    or f"# configuration file {available}:" in result.stdout
                )
            )
        except (OSError, RuntimeError):
            loaded = False
        self.check(
            "Сайт подключён в nginx",
            loaded,
            "проверьте sites-available, sites-enabled и include в nginx.conf",
        )

        https = self.config["NGINX_AUTO_HTTPS"] or self.config["NGINX_USE_HTTPS"]
        if https:
            cert = Path(self.config["NGINX_CERT_PATH"])
            key = Path(self.config["NGINX_CERT_KEY_PATH"])
            present = cert.is_file() and key.is_file()
            self.check(
                "Файлы TLS",
                present,
                "проверьте Certbot и пути NGINX_CERT_PATH/NGINX_CERT_KEY_PATH",
            )
            if present:
                valid = self.command_ok(
                    ["openssl", "x509", "-in", str(cert), "-noout", "-checkend", "0"]
                )
                self.check(
                    "Сертификат действителен", valid, "проверьте срок и имя сертификата"
                )
                if valid and not self.command_ok(
                    [
                        "openssl",
                        "x509",
                        "-in",
                        str(cert),
                        "-noout",
                        "-checkend",
                        "2592000",
                    ]
                ):
                    self.warn(
                        "Сертификат истекает менее чем через 30 дней; проверьте certbot renew --dry-run"
                    )
        scheme = "https" if https else "http"
        port = 443 if https else 80
        result = self.local_http(scheme, port, "/")
        self.check(
            f"Главная страница через {scheme.upper()}",
            result is not None
            and result.returncode == 0
            and self.http_code(result.stdout) == "200",
            "проверьте nginx, web-root и сертификат",
        )
        return https

    def local_http(self, scheme, port, path):
        domain = self.config["DOMAIN"]
        return run_command(
            [
                "curl",
                "--noproxy",
                "*",
                "--silent",
                "--show-error",
                "--max-time",
                "6",
                "--resolve",
                f"{domain}:{port}:127.0.0.1",
                "-D",
                "-",
                "-o",
                "/dev/null",
                "--write-out",
                "\nDOCTOR_CODE:%{http_code}\n",
                "--config",
                "-",
            ],
            timeout=8,
            input_text=f'url = "{scheme}://{domain}{path}"\n',
        )

    @staticmethod
    def http_code(headers):
        match = re.search(r"^DOCTOR_CODE:(\d{3})$", headers, re.MULTILINE)
        return match.group(1) if match else None

    def xui(self, https):
        self.check(
            "Служба 3x-ui",
            self.command_ok(["systemctl", "is-active", "--quiet", "x-ui"]),
            "проверьте systemctl status x-ui",
        )
        if not self.config["XUI_AUTO_CONFIGURE"]:
            self.warn("Автонастройка панели отключена; маршруты панели не проверялись")
            return
        routes = load_routes(self.config["XUI_STATE_FILE"], self.config["DOMAIN"])
        self.check(
            "Состояние 3x-ui",
            routes is not None,
            "проверьте закрытый access.json и повторите настройку панели",
        )
        if routes is None:
            return
        paths, ports = routes
        result = run_command(["ss", "-H", "-ltn"])
        self.check(
            "Порты панели и подписок доступны только локально",
            result is not None
            and result.returncode == 0
            and listening_only_locally(result.stdout, ports),
            "проверьте привязку 3x-ui к 127.0.0.1 и ::1",
        )
        if not https:
            self.warn("HTTPS nginx отключён; маршруты панели не проверялись")
            return
        for label, path, marker, accepted in (
            ("Панель", paths[0], "panel", {"200"}),
            (
                "Подписка",
                paths[1] + "__setup_healthcheck__",
                "subscription",
                {"200", "400", "404"},
            ),
            (
                "JSON-подписка",
                paths[2] + "__setup_healthcheck__",
                "subscription",
                {"200", "400", "404"},
            ),
            (
                "Clash-подписка",
                paths[3] + "__setup_healthcheck__",
                "subscription",
                {"200", "400", "404"},
            ),
        ):
            response = self.local_http("https", 443, path)
            self.check(
                f"Маршрут {label}",
                response is not None
                and response.returncode == 0
                and self.http_code(response.stdout) in accepted
                and f"x-3x-ui-route: {marker}" in response.stdout.lower(),
                "проверьте nginx proxy, порт и состояние 3x-ui",
            )

    def firewall(self):
        result = run_command(["ufw", "status", "verbose"])
        output = result.stdout if result and result.returncode == 0 else ""
        active = re.search(r"^Status:\s+active\s*$", output, re.MULTILINE) is not None
        self.check("UFW активен", active, "проверьте ufw status verbose")
        if not active:
            return
        policy = (
            re.search(
                r"^Default:\s+deny \(incoming\),\s*allow \(outgoing\)",
                output,
                re.MULTILINE,
            )
            is not None
        )
        self.check(
            "Политика UFW: deny incoming / allow outgoing",
            policy,
            "проверьте ufw default",
        )
        ports = self.config["WEB_TCP_PORTS"].split()
        if self.config["ENABLE_3X_UI_PORTS"]:
            ports += self.config["XRAY_TCP_PORTS"].split()
        for port in sorted({str(int(value)) for value in ports}, key=int):
            allowed = any(
                re.match(rf"^\s*{re.escape(port)}/tcp\s+ALLOW IN\b", line)
                for line in output.splitlines()
            )
            self.check(
                f"UFW разрешает {port}/tcp",
                allowed,
                "проверьте правила UFW; для Xray повторите scripts/install.sh firewall",
            )

    def fail2ban(self):
        self.check(
            "Служба Fail2Ban",
            self.command_ok(["systemctl", "is-active", "--quiet", "fail2ban"]),
            "проверьте systemctl status fail2ban",
        )
        self.check(
            "Ответ Fail2Ban",
            self.command_ok(["fail2ban-client", "ping"]),
            "проверьте fail2ban-client status",
        )
        self.check(
            "Jail SSH",
            self.command_ok(["fail2ban-client", "status", "sshd"]),
            "проверьте fail2ban-client status sshd",
        )
        if self.config["ENABLE_NGINX"] and self.config["ENABLE_NGINX_BOTSEARCH"]:
            self.check(
                "Jail nginx-botsearch",
                self.command_ok(["fail2ban-client", "status", "nginx-botsearch"]),
                "проверьте fail2ban-client status nginx-botsearch",
            )

    def run(self):
        print(f"╭─ Диагностика 3x-ui-setup: {self.config['DOMAIN']} ─╮")
        self.dns()
        https = False
        if self.config["ENABLE_NGINX"]:
            https = self.nginx()
        if self.config["ENABLE_UFW"]:
            self.firewall()
        if self.config["ENABLE_FAIL2BAN"]:
            self.fail2ban()
        if self.config["INSTALL_3X_UI"]:
            self.xui(https)
        print(f"Итог: проблем — {self.problems}, предупреждений — {self.warnings}.")
        print(
            "Проверены локальные маршруты; доступность снаружи зависит от DNS и firewall провайдера."
        )
        return 1 if self.problems else 0


def enabled(name):
    return os.environ.get(name, "false") in ("true", "yes", "1", "on")


def main():
    names = (
        "ENABLE_WWW",
        "ENABLE_NGINX",
        "NGINX_AUTO_HTTPS",
        "NGINX_USE_HTTPS",
        "ENABLE_UFW",
        "ENABLE_3X_UI_PORTS",
        "ENABLE_FAIL2BAN",
        "INSTALL_3X_UI",
        "XUI_AUTO_CONFIGURE",
        "ENABLE_NGINX_BOTSEARCH",
    )
    config = {name: enabled(name) for name in names}
    for name in (
        "DOMAIN",
        "NGINX_CERT_PATH",
        "NGINX_CERT_KEY_PATH",
        "XUI_STATE_FILE",
        "WEB_TCP_PORTS",
        "XRAY_TCP_PORTS",
    ):
        config[name] = os.environ[name]
    config["NGINX_SITE_DIR"] = os.environ.get(
        "NGINX_SITE_DIR", "/etc/nginx/sites-available"
    )
    config["NGINX_ENABLED_DIR"] = os.environ.get(
        "NGINX_ENABLED_DIR", "/etc/nginx/sites-enabled"
    )
    return Doctor(config).run()


if __name__ == "__main__":
    raise SystemExit(main())
