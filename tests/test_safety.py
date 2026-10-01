"""Failure-path checks using fake service commands; never touch host firewall."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]


class SafetyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:" + os.environ["PATH"],
            PROJECT_DIR=str(ROOT),
            SCRIPT_DIR=str(ROOT / "scripts"),
            DOMAIN="safe.example.org",
            LOG_FILE=str(self.base / "run.log"),
            SUMMARY_FILE=str(self.base / "summary.txt"),
            OPERATIONS=str(self.base / "operations"),
            NGINX_SITE_DIR=str(self.base / "sites-available"),
            NGINX_ENABLED_DIR=str(self.base / "sites-enabled"),
        )
        Path(self.env["NGINX_SITE_DIR"]).mkdir()
        Path(self.env["NGINX_ENABLED_DIR"]).mkdir()

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)

    def bash(self, body, extra=None):
        return subprocess.run(
            ["bash", "-c", "set -Eeuo pipefail\n" + body],
            env={**self.env, **(extra or {})},
            capture_output=True,
            text=True,
        )

    def test_active_ssh_session_port_is_preserved(self):
        self.command("systemctl", "exit 0")
        self.command("ss", "exit 0")
        self.command("sshd", 'echo "port 22"')
        result = self.bash(
            'source "$SCRIPT_DIR/lib/common.sh"\n'
            'source "$SCRIPT_DIR/lib/checks.sh"\n'
            "detect_ssh_ports",
            {"SSH_CONNECTION": "10.0.0.2 50000 10.0.0.1 2222"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2222", result.stdout.split())

    def test_ssh_socket_port_takes_priority_over_stale_sshd_config(self):
        self.command("systemctl", 'echo "Listen=[::]:2222 (Stream)"')
        self.command("ss", "exit 0")
        self.command("sshd", 'echo "port 22"')
        result = self.bash(
            'source "$SCRIPT_DIR/lib/common.sh"\n'
            'source "$SCRIPT_DIR/lib/checks.sh"\n'
            "detect_ssh_ports",
            {"SSH_CONNECTION": ""},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["2222"])

    def test_unrelated_process_blocks_firewall_before_mutation(self):
        self.command("sshd", 'echo "port 22"')
        self.command("systemctl", "exit 0")
        self.command("ip", "exit 0")
        self.command(
            "ss",
            'echo "LISTEN 0 128 0.0.0.0:8443 0.0.0.0:* users:((\\"other\\",pid=1,fd=2))"',
        )
        self.command("ufw", 'echo "$*" >> "$OPERATIONS"')
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/checks.sh"
install_packages_if_missing() { :; }
run_logged() { shift; "$@"; }
source "$SCRIPT_DIR/modules/30-firewall.sh"''',
            {
                "ENABLE_UFW": "true",
                "INSTALL_3X_UI": "false",
                "ENABLE_3X_UI_PORTS": "true",
                "XRAY_TCP_PORTS": "8443",
                "WEB_TCP_PORTS": "80 443",
                "UFW_RESET_RULES": "true",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("занят другим сервисом", result.stderr)
        self.assertFalse(Path(self.env["OPERATIONS"]).exists())

    def test_local_only_denies_precede_firewall_enable(self):
        self.command("sshd", 'echo "port 22"')
        self.command("systemctl", "exit 0")
        self.command("ip", "exit 0")
        self.command("ss", "exit 0")
        self.command(
            "ufw",
            """echo "$*" >> "$OPERATIONS"
if [ "$1" = status ]; then
  echo 'Status: active'
  grep -o '3x-ui-setup-local-only-[0-9]*' "$OPERATIONS" || true
fi""",
        )
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/checks.sh"
install_packages_if_missing() { :; }
run_logged() { shift; "$@"; }
xui_setup() { echo '2053 2096'; }
source "$SCRIPT_DIR/modules/30-firewall.sh"''',
            {
                "ENABLE_UFW": "true",
                "INSTALL_3X_UI": "true",
                "XUI_AUTO_CONFIGURE": "true",
                "ENABLE_3X_UI_PORTS": "false",
                "WEB_TCP_PORTS": "80 443",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        operations = Path(self.env["OPERATIONS"]).read_text()
        self.assertLess(
            operations.index("insert 1 deny 2053/tcp"),
            operations.index("--force enable"),
        )
        self.assertLess(
            operations.index("insert 1 deny 2096/tcp"),
            operations.index("--force enable"),
        )

    def test_nginx_failure_restores_previous_site(self):
        self.command(
            "nginx",
            """if [ ! -e "$OPERATIONS" ]; then touch "$OPERATIONS"; exit 1; fi
exit 0""",
        )
        self.command("systemctl", "exit 0")
        site = Path(self.env["NGINX_SITE_DIR"]) / self.env["DOMAIN"]
        site.write_text("# Managed by 3x-ui-setup\nOLD\n")
        (Path(self.env["NGINX_ENABLED_DIR"]) / self.env["DOMAIN"]).symlink_to(site)
        template = self.base / "new.conf"
        template.write_text("# Managed by 3x-ui-setup\nNEW\n")
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
render_template() { cp "$1" "$2"; }
nginx_apply_template "$TEST_TEMPLATE"''',
            {"TEST_TEMPLATE": str(template)},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(site.read_text(), "# Managed by 3x-ui-setup\nOLD\n")

    def test_unmanaged_nginx_site_is_refused(self):
        site = Path(self.env["NGINX_SITE_DIR"]) / self.env["DOMAIN"]
        site.write_text("user maintained\n")
        result = self.bash("""source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
nginx_site_guard""")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(site.read_text(), "user maintained\n")

    def test_managed_nginx_site_is_created_and_enabled(self):
        self.command(
            "nginx",
            'if [ "$1" = -T ]; then printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\nexit 0',
        )
        self.command("systemctl", "exit 0")
        template = self.base / "site.tpl"
        template.write_text("# Managed by 3x-ui-setup\nserver { listen 80; }\n")
        result = self.bash(
            'source "$SCRIPT_DIR/lib/common.sh"\n'
            'source "$SCRIPT_DIR/lib/nginx-site.sh"\n'
            'render_template() { cp "$1" "$2"; }\n'
            'nginx_apply_template "$TEST_TEMPLATE"',
            {"TEST_TEMPLATE": str(template)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        site = Path(self.env["NGINX_SITE_DIR"]) / self.env["DOMAIN"]
        enabled = Path(self.env["NGINX_ENABLED_DIR"]) / self.env["DOMAIN"]
        self.assertEqual(site.read_text(), template.read_text())
        self.assertTrue(enabled.is_symlink())
        self.assertEqual(enabled.resolve(), site)

    def test_certbot_failure_restores_previous_https_site(self):
        self.command(
            "nginx",
            'if [ "$1" = -T ]; then printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\nexit 0',
        )
        self.command("systemctl", "exit 0")
        self.command("certbot", "exit 1")
        self.command(
            "curl",
            'for url do :; done\ncat "$WEB_ROOT/.well-known/acme-challenge/${url##*/}"',
        )
        site = Path(self.env["NGINX_SITE_DIR"]) / self.env["DOMAIN"]
        site.write_text("# Managed by 3x-ui-setup\nPREVIOUS HTTPS\n")
        (Path(self.env["NGINX_ENABLED_DIR"]) / self.env["DOMAIN"]).symlink_to(site)
        webroot = self.base / "webroot"
        webroot.mkdir()
        (webroot / "index.html").write_text("keep website")
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { cp "$1" "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"''',
            {
                "WEB_ROOT": str(webroot),
                "NGINX_AUTO_HTTPS": "true",
                "NGINX_USE_HTTPS": "false",
                "NGINX_CERT_PATH": str(self.base / "missing.pem"),
                "NGINX_CERT_KEY_PATH": str(self.base / "missing-key.pem"),
                "LETSENCRYPT_EMAIL": "admin@example.org",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(site.read_text(), "# Managed by 3x-ui-setup\nPREVIOUS HTTPS\n")
        self.assertEqual((webroot / "index.html").read_text(), "keep website")

    def test_acme_probe_stops_before_certbot_and_restores_site(self):
        self.command(
            "nginx",
            'if [ "$1" = -T ]; then printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\nexit 0',
        )
        self.command("systemctl", "exit 0")
        self.command("curl", "printf 'wrong website'")
        self.command("certbot", 'echo called > "$OPERATIONS"')
        site = Path(self.env["NGINX_SITE_DIR"]) / self.env["DOMAIN"]
        site.write_text("# Managed by 3x-ui-setup\nPREVIOUS HTTPS\n")
        (Path(self.env["NGINX_ENABLED_DIR"]) / self.env["DOMAIN"]).symlink_to(site)
        webroot = self.base / "webroot"
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { cp "$1" "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"''',
            {
                "WEB_ROOT": str(webroot),
                "NGINX_AUTO_HTTPS": "true",
                "NGINX_USE_HTTPS": "false",
                "NGINX_CERT_PATH": str(self.base / "missing.pem"),
                "NGINX_CERT_KEY_PATH": str(self.base / "missing-key.pem"),
                "LETSENCRYPT_EMAIL": "admin@example.org",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Проверка HTTP-маршрута", result.stderr)
        self.assertEqual(site.read_text(), "# Managed by 3x-ui-setup\nPREVIOUS HTTPS\n")
        self.assertFalse(Path(self.env["OPERATIONS"]).exists())
        self.assertEqual(webroot.stat().st_mode & 0o777, 0o755)
        self.assertEqual(
            (webroot / ".well-known/acme-challenge").stat().st_mode & 0o777, 0o755
        )

    def test_unloaded_nginx_site_stops_before_certbot(self):
        self.command("nginx", "exit 0")
        self.command("systemctl", "exit 0")
        self.command("certbot", 'echo called > "$OPERATIONS"')
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { cp "$1" "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"''',
            {
                "WEB_ROOT": str(self.base / "webroot"),
                "NGINX_AUTO_HTTPS": "true",
                "NGINX_USE_HTTPS": "false",
                "NGINX_CERT_PATH": str(self.base / "missing.pem"),
                "NGINX_CERT_KEY_PATH": str(self.base / "missing-key.pem"),
                "LETSENCRYPT_EMAIL": "admin@example.org",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("не загрузил новый сайт", result.stderr)
        self.assertFalse(Path(self.env["OPERATIONS"]).exists())

    def test_www_acme_route_is_checked_before_certbot(self):
        self.command(
            "nginx",
            'if [ "$1" = -T ]; then printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\nexit 0',
        )
        self.command("systemctl", "exit 0")
        self.command("certbot", 'echo called > "$OPERATIONS"')
        self.command(
            "curl",
            'for url do :; done\ncase "$url" in http://www.*) printf wrong ;; *) cat "$WEB_ROOT/.well-known/acme-challenge/${url##*/}" ;; esac',
        )
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { cp "$1" "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"''',
            {
                "WEB_ROOT": str(self.base / "webroot"),
                "ENABLE_WWW": "true",
                "NGINX_AUTO_HTTPS": "true",
                "NGINX_USE_HTTPS": "false",
                "NGINX_CERT_PATH": str(self.base / "missing.pem"),
                "NGINX_CERT_KEY_PATH": str(self.base / "missing-key.pem"),
                "LETSENCRYPT_EMAIL": "admin@example.org",
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("www.safe.example.org", result.stderr)
        self.assertFalse(Path(self.env["OPERATIONS"]).exists())

    def test_nginx_template_listens_on_ipv6_when_available(self):
        if not Path("/proc/net/if_inet6").read_text().strip():
            self.skipTest("IPv6 is unavailable")
        output = self.base / "site.conf"
        result = self.bash(
            'source "$SCRIPT_DIR/lib/common.sh"\n'
            'source "$SCRIPT_DIR/lib/render-template.sh"\n'
            "detect_ssh_ports() { echo 22; }\n"
            'render_template "$PROJECT_DIR/templates/nginx/stub-https.conf.tpl" "$OUTPUT"',
            {
                "OUTPUT": str(output),
                "WEB_ROOT": str(self.base / "webroot"),
                "NGINX_CERT_PATH": str(self.base / "cert.pem"),
                "NGINX_CERT_KEY_PATH": str(self.base / "key.pem"),
                "XUI_STATE_FILE": str(self.base / "missing.json"),
                "FAIL2BAN_BANTIME": "1h",
                "FAIL2BAN_FINDTIME": "10m",
                "FAIL2BAN_MAXRETRY": "3",
                "FAIL2BAN_BANACTION": "ufw",
                "FAIL2BAN_IGNORE_IPS": "127.0.0.1/8 ::1",
                "ENABLE_NGINX_BOTSEARCH": "true",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        config = output.read_text()
        self.assertIn("listen [::]:80;", config)
        self.assertIn("listen [::]:443 ssl http2;", config)

    def test_old_placeholder_is_upgraded_but_custom_website_is_preserved(self):
        self.command(
            "nginx",
            'if [ "$1" = -T ]; then printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\nexit 0',
        )
        self.command("systemctl", "exit 0")
        webroot = self.base / "webroot"
        webroot.mkdir()
        page = webroot / "index.html"
        page.write_text(
            (ROOT / "templates/www/index.legacy.html.tpl")
            .read_text()
            .replace("{{DOMAIN}}", self.env["DOMAIN"])
        )
        script = '''source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { sed "s/{{DOMAIN}}/$DOMAIN/g" "$1" > "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"'''
        options = {
            "WEB_ROOT": str(webroot),
            "NGINX_AUTO_HTTPS": "false",
            "NGINX_USE_HTTPS": "false",
        }
        result = self.bash(script, options)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("<!-- Managed by 3x-ui-setup -->", page.read_text())
        self.assertIn(self.env["DOMAIN"], page.read_text())
        self.assertIn("localStorage", page.read_text())

        page.write_text("my own website\n")
        result = self.bash(script, options)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(page.read_text(), "my own website\n")

    def test_fail2ban_validation_failure_restores_previous_jail(self):
        self.command("fail2ban-client", "exit 1")
        self.command("systemctl", "exit 0")
        jail_dir = self.base / "jail.d"
        jail_dir.mkdir()
        jail = jail_dir / "3x-ui-setup.local"
        jail.write_text("# Managed by 3x-ui-setup\n[sshd]\nmaxretry = 5\n")
        user_jail = self.base / "jail.local"
        user_jail.write_text("[sshd]\nmaxretry = 10\n")
        result = self.bash(
            '''source "$SCRIPT_DIR/lib/common.sh"
install_packages_if_missing() { :; }
render_template() { cp "$1" "$2"; }
source "$SCRIPT_DIR/modules/40-fail2ban.sh"''',
            {
                "ENABLE_FAIL2BAN": "true",
                "FAIL2BAN_JAIL_DIR": str(jail_dir),
                "FAIL2BAN_LEGACY_FILE": str(user_jail),
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            jail.read_text(), "# Managed by 3x-ui-setup\n[sshd]\nmaxretry = 5\n"
        )
        self.assertEqual(user_jail.read_text(), "[sshd]\nmaxretry = 10\n")

    def test_bootstrap_prompt_value_cannot_execute_shell(self):
        source = (ROOT / "bootstrap.sh").read_text()
        function = source.split("set_env_value() {", 1)[1].split(
            "\nconfigure_minimal_env() {", 1
        )[0]
        marker = self.base / "injected"
        payload = f"$(touch {marker})"
        (self.base / ".env").write_text("DOMAIN=example.org\n")
        result = subprocess.run(
            [
                "bash",
                "-c",
                "set -Eeuo pipefail\nset_env_value() {" + function + "\n"
                'set_env_value LETSENCRYPT_EMAIL "$PAYLOAD"\n'
                'source "$SCRIPT_DIR/lib/env-file.sh"\n'
                "load_env_file .env\n"
                'test "$LETSENCRYPT_EMAIL" = "$PAYLOAD"',
            ],
            cwd=self.base,
            env={**self.env, "PAYLOAD": payload},
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(marker.exists())
        self.assertEqual(((self.base / ".env").stat().st_mode & 0o777), 0o600)

    def test_env_rejects_commands_without_running_them(self):
        marker = self.base / "injected"
        env_file = self.base / ".env"
        env_file.write_text(f'DOMAIN="safe.example.org"\ntouch {marker}\n')
        result = self.bash(
            'source "$SCRIPT_DIR/lib/env-file.sh"\nload_env_file "$ENV_PATH"',
            {"ENV_PATH": str(env_file)},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())

    def test_nginx_paths_reject_directive_injection_and_traversal(self):
        for path in (
            "/var/www/site; include /tmp/evil;",
            "/var/www/../etc",
            "/var/www//site",
        ):
            with self.subTest(path=path):
                result = self.bash(
                    'source "$SCRIPT_DIR/lib/common.sh"\n'
                    'source "$SCRIPT_DIR/lib/checks.sh"\n'
                    'WEB_ROOT="$CHECK_PATH"\nvalidate_config_path WEB_ROOT',
                    {"CHECK_PATH": path},
                )
                self.assertNotEqual(result.returncode, 0)

    def test_webroot_removal_rejects_critical_path(self):
        source = (ROOT / "scripts/modules/80-remove.sh").read_text()
        function = source.split("guard_remove_webroot() {", 1)[1].split(
            "\nremove_nginx() {", 1
        )[0]
        result = self.bash(
            'source "$SCRIPT_DIR/lib/common.sh"\n'
            'source "$SCRIPT_DIR/lib/checks.sh"\n'
            "guard_remove_webroot() {" + function + "\n"
            "WEB_ROOT=/var\nguard_remove_webroot",
        )
        self.assertNotEqual(result.returncode, 0)

    def test_bootstrap_checks_out_pinned_commit_after_branch_advances(self):
        remote = self.base / "remote"
        remote.mkdir()
        subprocess.run(["git", "init", "-q", str(remote)], check=True)
        subprocess.run(
            ["git", "-C", str(remote), "config", "user.email", "test@example.org"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(remote), "config", "user.name", "Test"], check=True
        )
        (remote / ".env.example").write_text("DOMAIN=example.org\n")
        subprocess.run(["git", "-C", str(remote), "add", ".env.example"], check=True)
        subprocess.run(["git", "-C", str(remote), "commit", "-qm", "old"], check=True)
        old = subprocess.check_output(
            ["git", "-C", str(remote), "rev-parse", "HEAD"], text=True
        ).strip()
        (remote / "new.txt").write_text("new\n")
        subprocess.run(["git", "-C", str(remote), "add", "new.txt"], check=True)
        subprocess.run(["git", "-C", str(remote), "commit", "-qm", "new"], check=True)
        source = (ROOT / "bootstrap.sh").read_text()
        function = source.split("prepare_repo() {", 1)[1].split(
            "\nset_env_value() {", 1
        )[0]
        checkout = self.base / "checkout"
        result = self.bash(
            "validate_install_dir() { :; }\n"
            'run_bootstrap_cmd() { shift; case "$1" in apt-get|env) return 0;; esac; "$@"; }\n'
            "prepare_repo() {" + function + "\nprepare_repo",
            {
                "REPO_URL": str(remote),
                "REPO_COMMIT": old,
                "INSTALL_DIR": str(checkout),
                "BOOTSTRAP_LOG": str(self.base / "bootstrap.log"),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        actual = subprocess.check_output(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True
        ).strip()
        self.assertEqual(actual, old)
        self.assertFalse((checkout / "new.txt").exists())


if __name__ == "__main__":
    unittest.main()
