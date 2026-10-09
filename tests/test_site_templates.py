"""Site template selection and browser-only behavior."""

import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]


class SiteTemplateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.webroot = self.base / "webroot"
        self.webroot.mkdir()
        self.available = self.base / "sites-available"
        self.enabled = self.base / "sites-enabled"
        self.available.mkdir()
        self.enabled.mkdir()
        self.env = dict(
            os.environ,
            PATH=f"{self.bin}:" + os.environ["PATH"],
            PROJECT_DIR=str(ROOT),
            SCRIPT_DIR=str(ROOT / "scripts"),
            DOMAIN="site.example.org",
            WEB_ROOT=str(self.webroot),
            NGINX_SITE_DIR=str(self.available),
            NGINX_ENABLED_DIR=str(self.enabled),
            LOG_FILE=str(self.base / "run.log"),
            SUMMARY_FILE=str(self.base / "summary.txt"),
            NGINX_AUTO_HTTPS="false",
            NGINX_USE_HTTPS="false",
        )
        nginx = self.bin / "nginx"
        nginx.write_text(
            '#!/bin/sh\nif [ "$1" = -T ]; then '
            'printf "# configuration file %s/%s:\\n" "$NGINX_ENABLED_DIR" "$DOMAIN"; fi\n'
        )
        nginx.chmod(0o755)
        systemctl = self.bin / "systemctl"
        systemctl.write_text("#!/bin/sh\nexit 0\n")
        systemctl.chmod(0o755)

    def install_site(self, selected):
        script = '''set -Eeuo pipefail
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/nginx-site.sh"
install_packages_if_missing() { :; }
render_template() { sed "s/{{DOMAIN}}/$DOMAIN/g" "$1" > "$2"; }
source "$SCRIPT_DIR/modules/20-nginx.sh"'''
        return subprocess.run(
            ["bash", "-c", script],
            env={**self.env, "SITE_TEMPLATE": selected},
            capture_output=True,
            text=True,
            check=False,
        )

    def test_selected_templates_replace_only_managed_page(self):
        page = self.webroot / "index.html"
        for selected, title in (
            ("tribe", "Племя"),
            ("numbers", "Генератор чисел"),
            ("notepad", "Блокнот"),
        ):
            with self.subTest(selected=selected):
                result = self.install_site(selected)
                self.assertEqual(result.returncode, 0, result.stderr)
                html = page.read_text()
                self.assertEqual(
                    html.splitlines()[1], "<!-- Managed by 3x-ui-setup -->"
                )
                self.assertIn(f"<title>{title} · site.example.org</title>", html)
                self.assertNotIn("{{DOMAIN}}", html)

        page.write_text("<h1>Мой сайт</h1>\n")
        result = self.install_site("numbers")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(page.read_text(), "<h1>Мой сайт</h1>\n")

    def test_unknown_template_fails_before_changing_page(self):
        page = self.webroot / "index.html"
        page.write_text("<!-- custom -->\n")
        result = self.install_site("../../etc/passwd")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Неизвестный шаблон", result.stderr)
        self.assertEqual(page.read_text(), "<!-- custom -->\n")

    def test_legacy_project_page_can_be_replaced(self):
        page = self.webroot / "index.html"
        page.write_text(
            (ROOT / "templates/www/index.legacy.html.tpl")
            .read_text()
            .replace("{{DOMAIN}}", "site.example.org")
        )
        result = self.install_site("notepad")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("<title>Блокнот · site.example.org</title>", page.read_text())

    def test_v1_1_1_placeholder_is_upgraded_but_modified_copy_is_preserved(self):
        template = (ROOT / "templates/www/index.legacy-v1.1.1.html.tpl").read_bytes()
        self.assertEqual(
            hashlib.sha256(template).hexdigest(),
            "fd538ae8e5fe4b8ac90fa38abee323c6cac6424c60f58aec1324913a5a890dbf",
        )
        old_page = template.decode().replace("{{DOMAIN}}", "site.example.org")
        page = self.webroot / "index.html"
        page.write_text(old_page)

        result = self.install_site("numbers")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("<title>Генератор чисел · site.example.org</title>", page.read_text())

        modified_page = old_page.replace("Сервер работает.", "Мой сервер работает.")
        page.write_text(modified_page)
        result = self.install_site("notepad")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(page.read_text(), modified_page)

    def test_bootstrap_choice_panel_describes_and_persists_selection(self):
        (self.base / ".env").write_text(
            'DOMAIN="site.example.org"\nSITE_TEMPLATE="tribe"\n'
        )
        source = (ROOT / "bootstrap.sh").read_text()
        setter = source.split("set_env_value() {", 1)[1].split(
            "\nconfigure_minimal_env() {", 1
        )[0]
        chooser = source.split("choose_site_template() {", 1)[1].split(
            "\ninstall_flow() {", 1
        )[0]
        script = (
            'set -Eeuo pipefail\nsource "$SCRIPT_DIR/lib/env-file.sh"\n'
            + "set_env_value() {"
            + setter
            + "\nchoose_site_template() {"
            + chooser
            + "\nchoose_site_template <<< '2'\n"
        )
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.base,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Генератор чисел", result.stdout)
        self.assertIn("История — в браузере", result.stdout)
        self.assertIn('SITE_TEMPLATE="numbers"', (self.base / ".env").read_text())

    @unittest.skipUnless(shutil.which("node"), "Node.js is unavailable")
    def test_inline_scripts_are_valid_and_have_no_network_calls(self):
        for selected in ("numbers", "notepad"):
            with self.subTest(selected=selected):
                page = ROOT / f"templates/www/index.{selected}.html.tpl"
                html = page.read_text()
                scripts = re.findall(r"<script>(.*?)</script>", html, re.S)
                self.assertEqual(len(scripts), 1)
                self.assertNotRegex(
                    scripts[0], r"\b(fetch|XMLHttpRequest|WebSocket|sendBeacon)\b"
                )
                self.assertNotRegex(html, r"<(?:script|link)[^>]+(?:src|href)=")
                js = self.base / f"{selected}.js"
                js.write_text(scripts[0])
                result = subprocess.run(
                    ["node", "--check", str(js)],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
