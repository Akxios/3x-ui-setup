"""Template rendering must not require unrelated live server components."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]


class RenderTemplateTests(unittest.TestCase):
    def test_plain_template_does_not_probe_ssh_or_panel_state(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            template = base / "index.tpl"
            output = base / "index.html"
            state = base / "access.json"
            state.write_text("invalid state")
            template.write_text("<title>{{DOMAIN}}</title>\n")
            env = {
                **os.environ,
                "SCRIPT_DIR": str(ROOT / "scripts"),
                "TEMPLATE": str(template),
                "OUTPUT": str(output),
                "XUI_STATE_FILE": str(state),
                "DOMAIN": "safe.example.org",
                "WEB_ROOT": str(base),
                "NGINX_CERT_PATH": str(base / "cert"),
                "NGINX_CERT_KEY_PATH": str(base / "key"),
                "FAIL2BAN_BANTIME": "1h",
                "FAIL2BAN_FINDTIME": "10m",
                "FAIL2BAN_MAXRETRY": "3",
                "FAIL2BAN_BANACTION": "ufw",
                "FAIL2BAN_IGNORE_IPS": "127.0.0.1/8",
                "ENABLE_NGINX_BOTSEARCH": "true",
            }
            script = '''set -Eeuo pipefail
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/render-template.sh"
detect_ssh_ports() { echo "unexpected SSH probe" >&2; return 1; }
xui_setup() { echo "unexpected panel probe" >&2; return 1; }
render_template "$TEMPLATE" "$OUTPUT"'''
            result = subprocess.run(
                ["bash", "-c", script],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(output.read_text(), "<title>safe.example.org</title>\n")
            self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
