#!/usr/bin/env python3
"""Export pi settings and extension metadata. Never copy extension source or credentials."""
import argparse
import json
import os
import shutil
from pathlib import Path

FILES = (
    "settings.json",
    "keybindings.json",
    "voice.json",
    "zentui.json",
    "trust.json",
    "sandbox-allowlist.json",
)
GUARD = Path("extensions/pi-safety-guards/config.json")


def package_source(item):
    if isinstance(item, str):
        return item
    if isinstance(item, dict):
        return item.get("source") or ""
    return ""


def package_version(source, modules):
    if source.startswith("npm:"):
        name = source[4:]
    elif source.startswith("https://github.com/"):
        name = source.rstrip("/").rsplit("/", 1)[-1]
    else:
        return None
    path = modules / name / "package.json"
    if not path.is_file():
        return None
    try:
        version = json.loads(path.read_text()).get("version")
    except (OSError, json.JSONDecodeError):
        return None
    return version if isinstance(version, str) else None


def export(source, output):
    output.mkdir(parents=True, exist_ok=True)
    for name in FILES:
        path = source / name
        if path.is_file() and not path.is_symlink():
            shutil.copy2(path, output / name)
    guard = source / GUARD
    if guard.is_file() and not guard.is_symlink():
        dest = output / GUARD
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(guard, dest)
    themes = source / "themes"
    if themes.is_dir() and not themes.is_symlink():
        for path in sorted(themes.iterdir()):
            if path.is_file() and not path.is_symlink() and path.suffix == ".json":
                dest = output / "themes" / path.name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, dest)
    local = []
    extensions = source / "extensions"
    if extensions.is_dir() and not extensions.is_symlink():
        for path in sorted(extensions.iterdir(), key=lambda item: item.name):
            entry = {"name": path.name}
            if path.is_symlink():
                entry["kind"] = "symlink"
                entry["target"] = os.readlink(path)
            elif path.is_dir():
                entry["kind"] = "dir"
            else:
                entry["kind"] = "file"
            local.append(entry)
    packages = []
    settings_path = source / "settings.json"
    if settings_path.is_file() and not settings_path.is_symlink():
        data = json.loads(settings_path.read_text())
        modules = source / "npm/node_modules"
        for item in data.get("packages", []):
            spec = package_source(item)
            if not spec:
                continue
            entry = {"source": spec}
            version = package_version(spec, modules)
            if version:
                entry["version"] = version
            packages.append(entry)
    (output / "extensions-manifest.json").write_text(
        json.dumps({"local": local, "packages": packages}, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        export(args.source, args.output)
    except (OSError, json.JSONDecodeError, TypeError, KeyError):
        parser.exit(1, "pi agent export failed: unsupported settings; source contents withheld.\n")


if __name__ == "__main__":
    main()
