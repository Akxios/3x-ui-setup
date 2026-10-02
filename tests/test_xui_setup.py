import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

SPEC = importlib.util.spec_from_file_location(
    "setup", Path(__file__).parents[1] / "scripts/lib/xui_setup.py"
)
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        env = patch.dict(
            os.environ,
            {
                "DOMAIN": "panel.example.org",
                "XUI_STATE_FILE": self.tmp.name + "/private/access.json",
                "XUI_ACCESS_FILE": self.tmp.name + "/access.txt",
            },
            clear=True,
        )
        env.start()
        self.addCleanup(env.stop)

    def prepare(self):
        with (
            patch.object(setup, "installed", return_value=False),
            patch.object(setup, "check_ports"),
        ):
            setup.prepare()
        return setup.load_pending_state()

    def test_current_endpoint_uses_http_when_certificate_is_empty(self):
        with patch.object(
            setup.subprocess,
            "check_output",
            side_effect=[
                "port: 2053\nwebBasePath: /private/\n",
                "cert: \nkey: \n",
            ],
        ):
            self.assertEqual(setup.current_endpoint(), "http://127.0.0.1:2053/private/")

    def test_current_endpoint_uses_https_when_certificate_is_set(self):
        with patch.object(
            setup.subprocess,
            "check_output",
            side_effect=[
                "port: 2053\nwebBasePath: /private/\n",
                "cert: /etc/letsencrypt/live/example/fullchain.pem\nkey: /etc/letsencrypt/live/example/privkey.pem\n",
            ],
        ):
            self.assertEqual(
                setup.current_endpoint(), "https://127.0.0.1:2053/private/"
            )

    def test_generated_credentials_survive_retry_and_files_are_private(self):
        first = self.prepare()
        second = self.prepare()
        self.assertEqual(first, second)
        self.assertGreaterEqual(len(first["password"]), 24)
        self.assertEqual(setup.pending_state_path().stat().st_mode & 0o777, 0o600)
        self.assertEqual(setup.state_path().parent.stat().st_mode & 0o777, 0o700)
        self.assertFalse(first["verified"])
        paths = setup.subscription_paths(first)
        self.assertEqual(len({first["panel_path"], *paths}), 4)
        for path in paths:
            self.assertRegex(path, r"^/[a-f0-9]{24}/$")
        self.assertEqual(first["sub_path"], second["sub_path"])
        self.assertFalse(setup.state_path().exists())

    def test_reconfiguration_keeps_active_state_until_verification(self):
        active = self.prepare()
        active["verified"] = True
        setup.save_state(active)
        with patch.dict(os.environ, {"XUI_PANEL_PORT": "2054"}):
            pending = self.prepare()
        self.assertEqual(pending["panel_port"], 2054)
        self.assertEqual(setup.load_state(), active)
        self.assertFalse(pending["verified"])

    def test_existing_subscription_paths_are_preserved(self):
        state = self.prepare()
        for key in ("sub_path", "sub_json_path", "sub_clash_path"):
            state.pop(key)
        setup.save_state(state)
        api = Mock()
        api.settings.return_value = {
            "webPort": state["panel_port"],
            "subPort": state["sub_port"],
            "subPath": "/existing-sub/",
            "subJsonPath": "/existing-json/",
            "subClashPath": "/existing-clash/",
        }
        with (
            patch.object(setup, "installed", return_value=True),
            patch.object(setup, "import_result", return_value={}),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "check_ports"),
        ):
            setup.prepare()
        self.assertEqual(
            setup.subscription_paths(setup.load_pending_state()),
            ("/existing-sub/", "/existing-json/", "/existing-clash/"),
        )

    def test_manual_subscription_path_change_is_preserved_on_retry(self):
        state = self.prepare()
        state["verified"] = True
        setup.save_state(state)
        api = Mock()
        api.settings.return_value = {
            "webPort": state["panel_port"],
            "subPort": state["sub_port"],
            "subPath": "/manual-sub/",
            "subJsonPath": state["sub_json_path"],
            "subClashPath": state["sub_clash_path"],
        }
        with (
            patch.object(setup, "installed", return_value=True),
            patch.object(setup, "import_result", return_value={}),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "check_ports"),
        ):
            setup.prepare()
        self.assertEqual(setup.load_pending_state()["sub_path"], "/manual-sub/")

    def test_existing_install_without_credentials_is_untouched(self):
        with (
            patch.object(setup, "installed", return_value=True),
            patch.object(setup, "import_result", return_value={}),
        ):
            with self.assertRaises(setup.SetupError):
                setup.prepare()
        self.assertFalse(setup.state_path().exists())

    def test_invalid_or_conflicting_ports_and_paths(self):
        for values in (
            {"XUI_PANEL_PORT": "443"},
            {"XUI_PANEL_PORT": "2096"},
            {"XUI_SUB_PORT": "70000"},
            {"XUI_WEB_BASE_PATH": "a;nginx"},
            {"XUI_WEB_BASE_PATH": "subjson"},
            {"EXTRA_TCP_PORTS": "2053"},
        ):
            with self.subTest(values=values), patch.dict(os.environ, values):
                with self.assertRaises(setup.SetupError):
                    self.prepare()

    def test_api_requires_success_and_sends_csrf_and_special_password_as_json(self):
        responses = [
            {"success": True, "obj": "token-1"},
            {"success": True},
            {"success": True, "obj": "token-2"},
            {"success": True, "obj": {"webPort": 2053, "subPort": 2096}},
            {"success": False, "msg": "DO_NOT_PRINT_PASSWORD"},
        ]
        opener = Mock()
        opener.open.side_effect = lambda *a, **k: io.StringIO(
            json.dumps(responses.pop(0))
        )
        password = 'spaces "quotes" $(not-executed) & пароль'
        with patch.object(setup.urllib.request, "build_opener", return_value=opener):
            panel = setup.Panel("http://127.0.0.1:2053/private/", "user", password)
            self.assertEqual(panel.settings()["webPort"], 2053)
            with self.assertRaises(setup.SetupError) as error:
                panel.request(panel.route + "update", {})
        self.assertNotIn("DO_NOT_PRINT", str(error.exception))
        login_request = opener.open.call_args_list[1].args[0]
        self.assertEqual(json.loads(login_request.data)["password"], password)
        self.assertEqual(login_request.get_header("X-csrf-token"), "token-1")
        self.assertEqual(
            opener.open.call_args_list[3].args[0].get_header("X-csrf-token"), "token-2"
        )

    def test_configure_preserves_unrelated_settings_and_checks_readback(self):
        state = self.prepare()
        api = Mock()
        api.route = "panel/api/setting/"
        settings = {
            "webPort": 2053,
            "subPort": 2096,
            "subJsonEnable": False,
            "subClashEnable": False,
            "tgBotEnable": True,
            "unrelated": "keep",
        }
        desired = setup.desired_settings(state)
        api.settings.side_effect = [settings.copy(), {**settings, **desired}]
        with (
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "check_ports"),
            patch.object(setup, "wait_panel", return_value="http://local/"),
            patch.object(setup.subprocess, "run") as run,
        ):
            setup.configure()
        payload = api.request.call_args.args[1]
        self.assertTrue(payload["tgBotEnable"])
        self.assertEqual(payload["unrelated"], "keep")
        self.assertEqual(payload["webListen"], "127.0.0.1")
        self.assertTrue(payload["subEnable"])
        self.assertTrue(payload["subJsonEnable"])
        self.assertTrue(payload["subClashEnable"])
        self.assertEqual(payload["subPath"], state["sub_path"])
        self.assertEqual(payload["subJsonPath"], state["sub_json_path"])
        self.assertEqual(payload["subClashPath"], state["sub_clash_path"])
        self.assertEqual(
            payload["subURI"], f"https://{state['domain']}{state['sub_path']}"
        )
        self.assertEqual(
            payload["subJsonURI"], f"https://{state['domain']}{state['sub_json_path']}"
        )
        run.assert_called_once_with(["systemctl", "restart", "x-ui"], check=True)
        self.assertFalse(setup.load_pending_state()["verified"])

    def test_failed_setting_update_does_not_restart(self):
        self.prepare()
        api = Mock()
        api.route = "panel/api/setting/"
        api.settings.return_value = {
            "webPort": 2053,
            "subPort": 2096,
            "subJsonEnable": False,
            "subClashEnable": False,
        }
        api.request.side_effect = setup.SetupError("API rejected")
        with (
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "check_ports"),
            patch.object(setup, "wait_panel", return_value="http://local/"),
            patch.object(setup.subprocess, "run") as run,
        ):
            with self.assertRaises(setup.SetupError):
                setup.configure()
            run.assert_not_called()

    def test_unchanged_settings_do_not_restart_panel(self):
        state = self.prepare()
        api = Mock()
        api.settings.return_value = setup.desired_settings(state)
        with (
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "wait_panel", return_value="http://local/"),
            patch.object(setup, "check_ports"),
            patch.object(setup.subprocess, "run") as run,
        ):
            setup.configure()
        api.request.assert_not_called()
        run.assert_not_called()
        self.assertFalse(setup.load_pending_state()["service_changed"])

    def test_unsupported_clash_version_stops_before_changes(self):
        self.prepare()
        api = Mock()
        api.settings.return_value = {
            "webPort": 2053,
            "subPort": 2096,
            "subJsonEnable": False,
        }
        with (
            patch.object(setup, "Panel", return_value=api),
            patch.object(setup, "current_endpoint", return_value="http://local/"),
            patch.object(setup, "wait_panel", return_value="http://local/"),
            patch.object(setup.subprocess, "run") as run,
        ):
            with self.assertRaisesRegex(setup.SetupError, "subClashEnable"):
                setup.configure()
            api.request.assert_not_called()
            run.assert_not_called()

    def test_proxy_preserves_base_path_and_overrides_blocking_regex(self):
        state = self.prepare()
        setup.save_state(state)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            setup.proxy()
        text = output.getvalue()
        self.assertIn("location ^~ " + state["panel_path"], text)
        for path in setup.subscription_paths(state):
            self.assertIn("location ^~ " + path, text)
        self.assertIn("proxy_pass http://127.0.0.1:2053;", text)
        self.assertNotIn(state["password"], text)

    def test_invalid_saved_subscription_path_cannot_enter_nginx_config(self):
        state = self.prepare()
        state["sub_path"] = "/bad;return 200;/"
        setup.save_state(state)
        with self.assertRaises(setup.SetupError):
            setup.proxy()

    def test_failed_https_does_not_publish_success_or_overwrite_card(self):
        self.prepare()
        card = Path(os.environ["XUI_ACCESS_FILE"])
        card.write_text("previous working card")
        result = subprocess.CompletedProcess(
            [], 0, stdout="HTTP/2 502\r\nX-3x-UI-Route: panel\r\n"
        )
        with patch.object(setup.subprocess, "run", return_value=result):
            with self.assertRaises(setup.SetupError):
                setup.verify()
        self.assertEqual(card.read_text(), "previous working card")
        self.assertFalse(setup.load_pending_state()["verified"])

    def test_state_write_failure_restores_previous_access_card(self):
        self.prepare()
        card = Path(os.environ["XUI_ACCESS_FILE"])
        card.write_text("previous working card")
        responses = [
            subprocess.CompletedProcess(
                [],
                0,
                stdout=(
                    "HTTP/2 200\r\nX-3x-UI-Route: panel\r\n"
                    if index == 0
                    else "HTTP/2 404\r\nX-3x-UI-Route: subscription\r\n"
                ),
            )
            for index in range(4)
        ]
        with (
            patch.object(setup.subprocess, "run", side_effect=responses),
            patch.object(setup.socket, "create_connection"),
            patch.object(setup, "save_state", side_effect=OSError("disk full")),
        ):
            with self.assertRaises(OSError):
                setup.verify()
        self.assertEqual(card.read_text(), "previous working card")
        self.assertFalse(setup.state_path().exists())

    def test_successful_verification_publishes_private_card(self):
        state = self.prepare()
        state["service_changed"] = True
        setup.save_pending_state(state)
        results = [
            subprocess.CompletedProcess([], 0, stdout=code)
            for code in (
                "HTTP/2 200\r\nX-3x-UI-Route: panel\r\n",
                "HTTP/2 404\r\nX-3x-UI-Route: subscription\r\n",
                "HTTP/2 404\r\nX-3x-UI-Route: subscription\r\n",
                "HTTP/2 404\r\nX-3x-UI-Route: subscription\r\n",
            )
        ]
        with (
            patch.object(setup.subprocess, "run", side_effect=results) as run,
            patch.object(setup.socket, "create_connection"),
        ):
            setup.verify()
        self.assertIn(
            state["sub_path"] + "__setup_healthcheck__",
            run.call_args_list[1].args[0][-1],
        )
        card = Path(os.environ["XUI_ACCESS_FILE"])
        card_text = card.read_text()
        self.assertIn("УСТАНОВКА ЗАВЕРШЕНА", card_text)
        self.assertIn(f"https://{state['domain']}{state['panel_path']}", card_text)
        self.assertIn(state["username"], card_text)
        self.assertIn(state["password"], card_text)
        self.assertIn("443/tcp — сайт, панель и подписка", card_text)
        self.assertIn(f"127.0.0.1:{state['panel_port']}", card_text)
        self.assertIn(f"127.0.0.1:{state['sub_port']}", card_text)
        self.assertIn(state["sub_path"] + "<ID-клиента>", card_text)
        self.assertIn(state["sub_json_path"] + "<ID-клиента>", card_text)
        self.assertIn(state["sub_clash_path"] + "<ID-клиента>", card_text)
        self.assertIn("клиентская подписка не проверена", card_text)
        self.assertIn("после создания inbound и клиента", card_text)
        self.assertEqual(card.stat().st_mode & 0o777, 0o600)
        self.assertTrue(setup.load_state()["verified"])
        self.assertFalse(setup.pending_state_path().exists())

    def test_access_card_does_not_claim_success_before_verification(self):
        state = self.prepare()
        card = setup.access_text(state)
        self.assertIn("НАСТРОЙКА НЕ ЗАВЕРШЕНА", card)
        self.assertNotIn("УСТАНОВКА ЗАВЕРШЕНА", card)
        self.assertIn("доступность сервиса не подтверждена", card)

    def test_generic_404_does_not_verify_subscription(self):
        self.prepare()
        results = [
            subprocess.CompletedProcess([], 0, stdout=code)
            for code in (
                "HTTP/2 200\r\nX-3x-UI-Route: panel\r\n",
                "HTTP/2 404\r\n",
            )
        ]
        with patch.object(setup.subprocess, "run", side_effect=results):
            with self.assertRaises(setup.SetupError):
                setup.verify()
        self.assertFalse(setup.load_pending_state()["verified"])
        self.assertFalse(Path(os.environ["XUI_ACCESS_FILE"]).exists())

    def test_real_nginx_template_renders_proxy_routes(self):
        state = self.prepare()
        setup.save_state(state)
        root = Path(__file__).parents[1]
        destination = Path(self.tmp.name) / "site.conf"
        env = dict(
            os.environ,
            PROJECT_DIR=str(root),
            SCRIPT_DIR=str(root / "scripts"),
            WEB_ROOT="/var/www/test",
            NGINX_CERT_PATH="/test/fullchain.pem",
            NGINX_CERT_KEY_PATH="/test/privkey.pem",
            CURRENT_SSH_PORTS="22",
            TEST_DEST=str(destination),
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$SCRIPT_DIR/lib/common.sh"\n'
                'source "$SCRIPT_DIR/lib/checks.sh"\n'
                'source "$SCRIPT_DIR/lib/xui.sh"\n'
                'source "$SCRIPT_DIR/lib/render-template.sh"\n'
                'render_template "$PROJECT_DIR/templates/nginx/stub-https.conf.tpl" "$TEST_DEST"',
            ],
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        rendered = destination.read_text()
        self.assertNotIn("{{", rendered)
        self.assertIn("location ^~ " + state["panel_path"], rendered)
        self.assertIn("proxy_set_header Host $host;", rendered)
        self.assertNotIn(state["password"], rendered)


if __name__ == "__main__":
    unittest.main()
