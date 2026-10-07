#!/usr/bin/env python3
"""Redact literal credentials in staged OpenCode JSON, not live configuration."""
import json
from pathlib import Path
import re
import sys

CREDENTIAL_KEYS = {"apikey", "password", "secret", "clientsecret", "accesstoken", "refreshtoken", "authorization"}


def redact(value):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            normalized = re.sub(r"[^a-z]", "", key.lower())
            if normalized in CREDENTIAL_KEYS and isinstance(item, str) and item:
                result[key] = item if item.startswith(("{env:", "${", "env:")) else "REDACTED"
            else:
                result[key] = redact(item)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


if __name__ == "__main__":
    root = Path(sys.argv[1])
    for path in root.rglob("*.json"):
        if path.is_symlink():
            raise SystemExit("OpenCode export failed: JSON symlink requires local review")
        try:
            original = json.loads(path.read_text())
        except (ValueError, UnicodeError):
            raise SystemExit("OpenCode export failed: invalid JSON; source contents withheld")
        safe = redact(original)
        if safe != original:
            path.write_text(json.dumps(safe, ensure_ascii=False, indent=2) + "\n")
