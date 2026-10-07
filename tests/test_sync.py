import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("clash_export", ROOT / "scripts/export-clash-party.py")
clash = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clash)


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "home"
        self.repo = self.base / "repo"
        self.home.mkdir()
        self.repo.mkdir()
        shutil.copy2(ROOT / "sync", self.repo / "sync")
        shutil.copytree(ROOT / "scripts", self.repo / "scripts", ignore=shutil.ignore_patterns("__pycache__"))
        self.env = dict(os.environ, HOME=str(self.home))

    def config(self, text):
        (self.repo / "dotfiles.conf").write_text(text)

    def source(self, name, content="source"):
        file = self.home / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        return file

    def run_sync(self, *args, input=""):
        return subprocess.run(["bash", str(self.repo / "sync"), *args], input=input,
                              text=True, capture_output=True, env=self.env)

    def test_mapping_excludes_and_scoped_deletion(self):
        self.config("~/.zshrc\n~/my project => backups/project\n  !secrets\n  !secrets.yaml\n  !tmp\n")
        self.source(".zshrc")
        self.source("my project/main.py")
        self.source("my project/package-lock.json")
        for name in ("node_modules/lib.js", ".git/config", ".esphome/build/main.cpp", ".venv/bin/python",
                     "secrets/key.env", "secrets.yaml", "tmp/dump.json", "picture.png", "PHOTO.JPG", "design.drawio"):
            self.source("my project/" + name, "DO_NOT_COPY")
        unrelated = self.repo / "unrelated.txt"
        unrelated.write_text("keep")
        result = self.run_sync("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.repo / ".zshrc").is_file())
        target = self.repo / "backups/project"
        self.assertEqual(sorted(p.name for p in target.iterdir()), ["main.py", "package-lock.json"])
        (self.home / "my project/main.py").unlink()
        result = self.run_sync("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((target / "main.py").exists())
        self.assertEqual(unrelated.read_text(), "keep")

    def test_cancel_dry_run_and_custom_config(self):
        self.source("hello/config.txt")
        self.config("~/hello\n")
        for args, answer in (((), "n\n"), (("--dry-run",), "")):
            result = self.run_sync(*args, input=answer)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((self.repo / "hello").exists())
        custom = self.base / "custom.conf"
        custom.write_text("~/hello => alternate\n")
        result = self.run_sync(str(custom), input="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.repo / "alternate/config.txt").exists())

    def test_unsafe_destination_and_symlink(self):
        self.source("hello/code")
        for destination in ("../escape", ".git/config", "/tmp/outside"):
            self.config(f"~/hello => {destination}\n")
            self.assertNotEqual(self.run_sync("--yes").returncode, 0)
        (self.repo / "outside").symlink_to(self.home, target_is_directory=True)
        self.config("~/hello => outside/backup\n")
        self.assertNotEqual(self.run_sync("--yes").returncode, 0)
        self.assertFalse((self.home / "backup").exists())

    def test_clash_uses_exporter_not_raw_copy(self):
        app = "Library/Application Support/mihomo-party"
        self.source(app + "/config.yaml", "appTheme: dark\ngistAgeSecretKey: DO_NOT_COPY\n")
        self.source(app + "/profile.yaml", "url: https://subscription.example/DO_NOT_COPY\n")
        self.config(f"~/{app} => backups/clash-party\n")
        result = self.run_sync("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        target = self.repo / "backups/clash-party"
        self.assertFalse((target / "profile.yaml").exists())
        self.assertNotIn("DO_NOT_COPY", (target / "config.yaml").read_text())
        self.assertEqual(yaml.safe_load((target / "config.yaml").read_text())["appTheme"], "dark")

    def test_opencode_redaction_does_not_change_live_config(self):
        content = json.dumps({"provider": {"local": {"options": {"apiKey": "FIXTURE_SECRET"}},
                                           "remote": {"options": {"apiKey": "{env:REMOTE_KEY}"}}}})
        source = self.source(".config/opencode/opencode.json", content)
        self.source(".config/opencode/opencode.json.bak", content)
        self.config("~/.config/opencode\n  !*.bak\n")
        result = self.run_sync("--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        target = self.repo / ".config/opencode/opencode.json"
        self.assertNotIn("FIXTURE_SECRET", target.read_text())
        self.assertIn("REDACTED", target.read_text())
        self.assertIn("{env:REMOTE_KEY}", target.read_text())
        self.assertEqual(source.read_text(), content)
        self.assertFalse(target.with_suffix(".json.bak").exists())

    def test_parse_failure_does_not_modify_repository(self):
        app = "Library/Application Support/mihomo-party"
        self.source(app + "/config.yaml", "appTheme: [invalid\n")
        self.source("hello")
        self.config(f"~/hello\n~/{app} => backups/clash-party\n")
        result = self.run_sync("--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.repo / "hello").exists())
        self.assertFalse((self.repo / "backups").exists())


class ClashTests(unittest.TestCase):
    def test_unknown_fields_credentials_and_urls_are_removed(self):
        secret = "FIXTURE_SECRET"
        app = clash.application({"appTheme": "dark", "gistAgeSecretKey": secret, "apiKey": secret,
                                 "nameserverPolicy": {"example.com": ["https://dns.alidns.com/dns-query"]},
                                 "sysProxy": {"enable": True, "password": secret}})
        core = clash.core({"mixed-port": 7890, "secret": secret, "authentication": [secret],
                           "proxies": [{"password": secret}], "proxy-providers": {"x": {"url": secret}},
                           "dns": {"enable": True, "unknown": secret,
                                   "nameserver": ["https://dns.alidns.com/dns-query", "https://private.example/" + secret,
                                                  "https://dns.alidns.com/dns-query?token=" + secret]},
                           "tun": {"enable": True, "password": secret}})
        over = clash.override({"proxies+": [{"name": "direct", "type": "direct"},
                                            {"type": "ss", "server": secret, "password": secret}],
                               "rule-providers": {"safe": {"type": "http", "url": "https://raw.githubusercontent.com/szkane/ClashRuleSet/main/rule.yaml", "headers": {"Authorization": secret}},
                                                  "private": {"type": "http", "url": "https://private.example/" + secret}},
                               "+rules": ["DOMAIN,example.com,DIRECT"], "unknown": secret})
        text = json.dumps([app, core, over])
        self.assertNotIn(secret, text)
        self.assertTrue(core["tun"]["enable"])
        self.assertEqual(core["mixed-port"], 7890)
        self.assertEqual(len(core["dns"]["nameserver"]), 1)
        self.assertNotIn("private", over["rule-providers"])
        self.assertEqual(over["proxies+"], [{"name": "direct", "type": "direct"}])

    def test_substore_relationships_and_quick_settings(self):
        secret = "FIXTURE_SECRET"
        quick = {"type": "Quick Setting Operator", "args": {"udp": "DEFAULT", "useless": "DISABLED", "token": secret, "tfo": secret}}
        data = {"subs": [{"name": "alpha", "url": secret, "process": [quick]},
                         {"name": "beta", "content": secret, "process": [{"type": "Script Operator", "args": secret}]}],
                "collections": [{"name": secret, "subscriptions": ["beta", "alpha"], "process": [quick]}],
                "tokens": [secret], "settings": {"secret": secret}, "archives": [secret]}
        result = clash.substore(data)
        self.assertNotIn(secret, json.dumps(result))
        self.assertEqual(result["collections"][0]["subscriptions"], ["subscription-2", "subscription-1"])
        self.assertEqual(result["subs"][0]["process"][0]["args"], {"udp": "DEFAULT", "useless": "DISABLED"})
        self.assertEqual(result["subs"][1]["process"], [])

    def test_scripts_require_review(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "source"
            source.mkdir()
            (source / "nju-netmon.sh").write_text("token=FIXTURE_SECRET")
            with self.assertRaisesRegex(ValueError, "review"):
                clash.export(source, Path(temp) / "output")


if __name__ == "__main__":
    unittest.main()
