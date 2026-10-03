"""Read-only diagnostics must detect failures without exposing credentials."""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location(
    "setup_doctor", ROOT / "scripts/lib/doctor.py"
)
doctor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(doctor)


class DoctorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        available = self.base / "sites-available"
        enabled = self.base / "sites-enabled"
        available.mkdir()
        enabled.mkdir()
        site = available / "safe.example.org"
        site.write_text("# Managed by 3x-ui-setup\n")
        (enabled / site.name).symlink_to(site)
        self.cert = self.base / "cert.pem"
        self.key = self.base / "key.pem"
        self.cert.write_text("certificate fixture")
        self.key.write_text("key fixture")
        self.state = self.base / "access.json"
        self.state.write_text(
            json.dumps(
                {
                    "domain": "safe.example.org",
                    "panel_path": "/secretPanel/",
                    "sub_path": "/secretSub/",
                    "sub_json_path": "/secretJson/",
                    "sub_clash_path": "/secretClash/",
                    "panel_port": 2053,
                    "sub_port": 2096,
                    "password": "very-secret-password",
                }
            )
        )
        self.config = {
            "DOMAIN": "safe.example.org",
            "ENABLE_WWW": False,
            "ENABLE_NGINX": True,
            "NGINX_AUTO_HTTPS": True,
            "NGINX_USE_HTTPS": False,
            "NGINX_CERT_PATH": str(self.cert),
            "NGINX_CERT_KEY_PATH": str(self.key),
            "NGINX_SITE_DIR": str(available),
            "NGINX_ENABLED_DIR": str(enabled),
            "ENABLE_UFW": True,
            "ENABLE_3X_UI_PORTS": True,
            "WEB_TCP_PORTS": "80 443",
            "XRAY_TCP_PORTS": "8443",
            "ENABLE_FAIL2BAN": True,
            "ENABLE_NGINX_BOTSEARCH": True,
            "INSTALL_3X_UI": True,
            "XUI_AUTO_CONFIGURE": True,
            "XUI_STATE_FILE": str(self.state),
        }

    def command(self, args, timeout=8, input_text=None):
        if args[:2] == ["getent", "ahosts"]:
            output = "192.0.2.10 STREAM safe.example.org\n"
        elif args[:2] == ["nginx", "-T"]:
            output = f"# configuration file {self.config['NGINX_ENABLED_DIR']}/safe.example.org:\n"
        elif args[:3] == ["ufw", "status", "verbose"]:
            output = (
                "Status: active\nDefault: deny (incoming), allow (outgoing)\n"
                "80/tcp ALLOW IN Anywhere\n443/tcp ALLOW IN Anywhere\n"
                "8443/tcp ALLOW IN Anywhere\n"
            )
        elif args[:3] == ["ss", "-H", "-ltn"]:
            output = (
                "LISTEN 0 128 127.0.0.1:2053 0.0.0.0:*\n"
                "LISTEN 0 128 127.0.0.1:2096 0.0.0.0:*\n"
            )
        elif args and args[0] == "curl":
            url = input_text or ""
            route = "panel" if "/secretPanel/" in url else "subscription"
            code = "404" if "__setup_healthcheck__" in url else "200"
            output = f"HTTP/2 {code}\nx-3x-ui-route: {route}\n\nDOCTOR_CODE:{code}\n"
        else:
            output = ""
        return subprocess.CompletedProcess(args, 0, output, "")

    def test_healthy_server_and_secrets_are_not_printed(self):
        output = io.StringIO()
        with (
            patch.object(doctor, "run_command", self.command),
            contextlib.redirect_stdout(output),
        ):
            code = doctor.Doctor(self.config).run()
        self.assertEqual(code, 0, output.getvalue())
        self.assertIn("проблем — 0", output.getvalue())
        self.assertNotIn("very-secret-password", output.getvalue())
        self.assertNotIn("secretPanel", output.getvalue())

    def test_public_management_bind_is_a_failure(self):
        original = self.command

        def command(args, timeout=8, input_text=None):
            if args[:3] == ["ss", "-H", "-ltn"]:
                return subprocess.CompletedProcess(
                    args, 0, "LISTEN 0 128 0.0.0.0:2053 0.0.0.0:*\n", ""
                )
            return original(args, timeout, input_text)

        output = io.StringIO()
        with (
            patch.object(doctor, "run_command", command),
            contextlib.redirect_stdout(output),
        ):
            code = doctor.Doctor(self.config).run()
        self.assertEqual(code, 1)
        self.assertIn(
            "Порты панели и подписок доступны только локально", output.getvalue()
        )

    def test_invalid_state_or_symlink_is_rejected(self):
        self.assertEqual(
            doctor.load_routes(self.state, "safe.example.org"),
            (
                ("/secretPanel/", "/secretSub/", "/secretJson/", "/secretClash/"),
                (2053, 2096),
            ),
        )
        linked = self.base / "linked.json"
        linked.symlink_to(self.state)
        self.assertIsNone(doctor.load_routes(linked, "safe.example.org"))
        data = json.loads(self.state.read_text())
        data["panel_path"] = "/bad\nHeader/"
        self.state.write_text(json.dumps(data))
        self.assertIsNone(doctor.load_routes(self.state, "safe.example.org"))

    def test_secret_routes_are_passed_to_curl_on_stdin(self):
        calls = []

        def command(args, timeout=8, input_text=None):
            calls.append((args, input_text))
            return self.command(args, timeout, input_text)

        with (
            patch.object(doctor, "run_command", command),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            self.assertEqual(doctor.Doctor(self.config).run(), 0)
        curl_calls = [(args, body) for args, body in calls if args[0] == "curl"]
        self.assertTrue(curl_calls)
        self.assertTrue(any("secretPanel" in body for _, body in curl_calls))
        self.assertTrue(
            all("secretPanel" not in " ".join(args) for args, _ in curl_calls)
        )

    def test_child_commands_do_not_inherit_panel_password(self):
        with (
            patch.dict(os.environ, {"XUI_PASSWORD": "very-secret-password"}),
            patch.object(doctor.subprocess, "run") as command,
        ):
            command.return_value = subprocess.CompletedProcess(
                ["nginx", "-t"], 0, "", ""
            )
            doctor.run_command(["nginx", "-t"])
        self.assertNotIn("XUI_PASSWORD", command.call_args.kwargs["env"])


if __name__ == "__main__":
    unittest.main()
