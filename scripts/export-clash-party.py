#!/usr/bin/env python3
"""Export software settings, never the original subscription/profile stores."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
from urllib.parse import urlsplit

import yaml

APP_KEYS = set("""core enableSmartCore enableSmartOverride smartCoreUseLightGBM
smartCoreCollectData silentStart appTheme useWindowFrame proxyInTray showCurrentProxyInTray
 enableTrafficLogger trayProxyGroupStyle disableTrayIconColor maxLogDays maxLogFileSize
 disableAppLog disableCoreLog proxyCols connectionDirection connectionOrderBy useSubStore
 autoQuitWithoutCore autoQuitWithoutCoreDelay autoQuitWithoutCoreMode proxyDisplayMode
 proxyDisplayOrder autoCheckUpdate autoUpdateProfileOnStart silentUpdate autoCloseConnection
 subscriptionTimeout gistAgeEncrypt networkInfoCardOrder useNameserverPolicy controlDns
 controlSniff floatingWindowCompatMode disableHardwareAcceleration hideConnectionCardWave
 siderOrder lastSelectedSiderCard siderWidth triggerMainWindowBehavior showMixedPort
 enableMixedPort showSocksPort enableSocksPort showHttpPort enableHttpPort showRedirPort
 enableRedirPort showTproxyPort enableTproxyPort testProfileOnStart coreStartupMode
 useHotReloadProfile hotReloadProfileAutoCloseConnection smartCoreStrategy language envType
 autoCloseConnectionOnlyGroup customTrayIcon disableDnsOverrideGuard modeSelected
 operationMode trayTrafficTextColor""".split())
CORE_KEYS = set("""external-controller external-ui external-ui-url ipv6 mode mixed-port
 socks-port port redir-port tproxy-port allow-lan unified-delay tcp-concurrent log-level
 find-process-mode bind-address lan-allowed-ips lan-disallowed-ips skip-auth-prefixes
 geo-auto-update geo-update-interval lgbm-auto-update lgbm-update-interval lgbm-url
 geodata-mode geox-url""".split())
TUN_KEYS = set("""enable stack auto-route auto-redirect auto-detect-interface dns-hijack
 route-exclude-address mtu device inet4-route-exclude-address strict-route""".split())
DNS_KEYS = set("""enable ipv6 enhanced-mode fake-ip-range fake-ip-filter use-hosts
 use-system-hosts respect-rules default-nameserver nameserver proxy-server-nameserver
 direct-nameserver fallback direct-nameserver-follow-policy fake-ip-filter-mode listen""".split())
SNIFFER_KEYS = set("""enable parse-pure-ip force-dns-mapping override-destination
 skip-domain skip-dst-address""".split())
QUICK_KEYS = {"useless", "udp", "scert", "tfo", "vmess aead", "reuse", "block-quic", "ecn", "ip-version"}
# Only the public resources used by this installation are admitted. New sources
# need review rather than accidentally exporting a private subscription URL.
PUBLIC_PREFIXES = (
    "https://github.com/MetaCubeX/meta-rules-dat/",
    "https://github.com/Zephyruso/zashboard/",
    "https://raw.githubusercontent.com/szkane/ClashRuleSet/",
    "https://raw.githubusercontent.com/appshubcc/bett-rules/",
    "https://www.gstatic.com/generate_204",
)
DROP = object()


def safe_url(value):
    parsed = urlsplit(value)
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        return False
    if value.startswith(PUBLIC_PREFIXES):
        return True
    if parsed.scheme in {"https", "tls", "quic"}:
        public_dns = parsed.hostname in {
            "dns.alidns.com", "doh.pub", "dns.google", "cloudflare-dns.com",
            "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1", "223.5.5.5", "223.6.6.6",
        }
        return public_dns and parsed.path in {"", "/dns-query"}
    return False


def clean(value):
    """Allow basic values; URL-bearing fields cannot smuggle arbitrary addresses."""
    if isinstance(value, str):
        if re.search(r"(?i)(?:token|password|secret|authorization)[=:]", value):
            return DROP
        if "://" in value and not safe_url(value):
            return DROP
        return value
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, list):
        return [x for v in value if (x := clean(v)) is not DROP]
    return DROP  # dictionaries require an explicit field projection


def project(data, keys):
    if not isinstance(data, dict):
        raise ValueError("expected a configuration mapping")
    result = {}
    for key, value in data.items():
        if key in keys:
            safe = clean(value)
            if safe is not DROP:
                result[key] = safe
    return result


def policy(data):
    if not isinstance(data, dict):
        return {}
    return {k: v for k, value in data.items()
            if isinstance(k, str) and "://" not in k and (v := clean(value)) is not DROP}


def tun(data):
    return project(data, TUN_KEYS | {k + "+" for k in TUN_KEYS})


def dns(data):
    result = project(data, DNS_KEYS | {k + "+" for k in DNS_KEYS})
    if "fallback-filter" in data:
        result["fallback-filter"] = project(data["fallback-filter"], {"geoip", "geoip-code", "geosite", "ipcidr", "domain"})
    for key in ("nameserver-policy", "nameserver-policy!", "nameserver-policy+"):
        if key in data:
            result[key] = policy(data[key])
    return result


def application(data):
    result = project(data, APP_KEYS)
    icons = data.get("customTrayIcons")
    if isinstance(icons, dict):
        kept = {}
        for key, value in icons.items():
            if isinstance(value, str) and value.startswith("data:image/"):
                safe = clean(value)
                if safe is not DROP:
                    kept[key] = safe
        if kept:
            result["customTrayIcons"] = kept
    if "sysProxy" in data:
        result["sysProxy"] = project(data["sysProxy"], {"enable", "mode"})
    if "nameserverPolicy" in data:
        result["nameserverPolicy"] = policy(data["nameserverPolicy"])
    if "networkLatencyTargets" in data:
        result["networkLatencyTargets"] = [project(x, {"name", "url"}) for x in data["networkLatencyTargets"] if isinstance(x, dict)]
    return result


def core(data):
    result = project(data, CORE_KEYS)
    if "geox-url" in data:
        result["geox-url"] = project(data["geox-url"], {"geoip", "geosite", "mmdb", "asn"})
    for key, transform in (("tun", tun), ("dns", dns)):
        if key in data:
            result[key] = transform(data[key])
    if "profile" in data:
        result["profile"] = project(data["profile"], {"store-selected", "store-fake-ip"})
    if "sniffer" in data:
        sniffer = data["sniffer"]
        result["sniffer"] = project(sniffer, SNIFFER_KEYS)
        if "sniff" in sniffer:
            result["sniffer"]["sniff"] = {k: project(v, {"ports", "override-destination"})
                                          for k, v in sniffer["sniff"].items() if k in {"HTTP", "TLS", "QUIC"}}
    return result


def override(data):
    result = project(data, {"ipv6", "rules", "+rules", "rules+"})
    for key, transform in (("tun", tun), ("dns", dns)):
        if key in data:
            result[key] = transform(data[key])
    if "rule-providers" in data:
        result["rule-providers"] = {}
        for name, item in data["rule-providers"].items():
            safe = project(item, {"type", "behavior", "format", "path", "url", "interval"})
            if item.get("type") == "http" and "url" not in safe:
                continue
            result["rule-providers"][name] = safe
    for key in ("proxies", "proxies+"):
        if key in data:
            result[key] = [project(x, {"name", "type", "udp", "ip-version"})
                           for x in data[key] if x.get("type") in {"direct", "reject", "DIRECT", "REJECT"}]
    for key in ("proxy-groups", "+proxy-groups", "proxy-groups+"):
        if key in data:
            result[key] = [project(x, {"name", "type", "include-all", "include-all-proxies", "include-all-providers",
                                       "filter", "exclude-filter", "proxies", "url", "expected-status", "interval", "lazy", "tolerance"})
                           for x in data[key]]
    return result


def processes(items):
    result = []
    for item in items:
        if item.get("type") != "Quick Setting Operator":
            print("  Clash: skipped an unreviewed Sub-Store processor")
            continue
        args = item.get("args", {})
        # Quick settings are booleans/numbers or the ip-version enum, not scripts.
        safe = {k: v for k, v in args.items() if k in QUICK_KEYS and
                (isinstance(v, (bool, int)) or (isinstance(v, str) and v in {
                    "DEFAULT", "ENABLED", "DISABLED", "IPV4", "IPV6", "IPV4-PREFER", "IPV6-PREFER",
                    "dual", "ipv4", "ipv6", "ipv4-prefer", "ipv6-prefer", "default"}))}
        result.append({"type": "Quick Setting Operator", "args": safe})
    return result


def substore(data):
    names = {item["name"]: f"subscription-{i}" for i, item in enumerate(data.get("subs", []), 1)}
    result = {"subs": [], "collections": []}
    for item in data.get("subs", []):
        result["subs"].append({"name": names[item["name"]], "process": processes(item.get("process", []))})
    for i, item in enumerate(data.get("collections", []), 1):
        safe = project(item, {"mergeSources", "ignoreFailedRemoteSub", "passThroughUA", "firstSubFlow"})
        safe.update(name=f"collection-{i}", subscriptions=[names[n] for n in item.get("subscriptions", []) if n in names],
                    process=processes(item.get("process", [])))
        result["collections"].append(safe)
    return result


def export(source, output, extras=()):
    def load(name):
        return yaml.safe_load((source / name).read_text()) or {}

    def save(name, value):
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(value, allow_unicode=True, sort_keys=False))

    output.mkdir(parents=True, exist_ok=True)
    for name, transform in (("config.yaml", application), ("mihomo.yaml", core)):
        if (source / name).is_file():
            save(name, transform(load(name)))
    if (source / "override.yaml").is_file():
        manifest = {"items": []}
        reviewed_js = {
            "stable-rate-exit": "e51a0863dd802c79a3a46c82d434041a17796f23212b3a028b83ebc1d7218743",
        }
        for item in load("override.yaml").get("items", []):
            ext = item.get("ext")
            ident = str(item["id"])
            if not re.fullmatch(r"[A-Za-z0-9_-]+", ident) or ext not in {"yaml", "js"}:
                raise ValueError("unsafe override id")
            rel = f"override/{ident}.{ext}"
            src = source / rel
            if ext == "yaml" and src.is_file():
                manifest["items"].append(project(item, {"id", "name", "type", "ext", "global"}))
                save(rel, override(load(rel)))
            elif ext == "js":
                expected = reviewed_js.get(ident)
                digest = hashlib.sha256(src.read_bytes()).hexdigest() if src.is_file() else ""
                if expected is None or digest != expected:
                    raise ValueError("unreviewed JS override")
                manifest["items"].append(project(item, {"id", "name", "type", "ext", "global"}))
                dest = output / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dest)
            else:
                raise ValueError("unreviewed override")
        save("override.yaml", manifest)
    if (source / "substore/sub-store.json").is_file():
        result = substore(json.loads((source / "substore/sub-store.json").read_text()))
        (output / "substore-structure.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    # Scripts are executable source, so pin the reviewed versions. Future edits
    # require review instead of silently copying potentially embedded secrets.
    for name, digest in REVIEWED_SCRIPTS.items():
        path = source / name
        if not path.is_file():
            continue
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"{name} changed: review it and update REVIEWED_SCRIPTS before backup")
        dest = output / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
    for extra in extras:
        digest = REVIEWED_EXTRAS.get(extra.name)
        if digest is None or hashlib.sha256(extra.read_bytes()).hexdigest() != digest:
            raise ValueError("unreviewed extra")
        shutil.copy2(extra, output / extra.name)


REVIEWED_SCRIPTS = {
    "nju-captive-tun.sh": "3f5def6c75c291ce5ba208593ad30635244f53fcd54dd196f8ba87a4961e3e55",
    "nju-netmon.sh": "044c0f9b2a80acef7da8d22910d856fee3469b1472a58dc6c4c9dc18ca308200",
    "dns-cache-helper/dns_cache_helper.py": "35a871734b438912b9cac6938e81cad9a695c6e388831f5d9a8f99b845b9966b",
}
REVIEWED_EXTRAS = {
    "party.clash.dns-cache-helper.plist": "40741df6e01921418c0fc5ccaa0fa312503b1ac78b8f1cb10203587d0d5df603",
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--source", type=Path, default=Path.home() / "Library/Application Support/mihomo-party")
    args = parser.parse_args()
    extras = []
    plist = Path.home() / "Library/LaunchAgents/party.clash.dns-cache-helper.plist"
    if plist.is_file():
        extras.append(plist)
    try:
        export(args.source, args.output, extras)
    except yaml.YAMLError:
        parser.exit(1, "Clash export failed: invalid YAML; source contents withheld.\n")
    except json.JSONDecodeError:
        parser.exit(1, "Clash export failed: invalid JSON; source contents withheld.\n")
    except (ValueError, TypeError, KeyError, AttributeError, OSError):
        parser.exit(1, "Clash export failed: unsupported structure or changed helper script; review locally.\n")
