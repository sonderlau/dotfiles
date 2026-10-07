#!/bin/bash
# Local network flight recorder. No internet required.
# Quick dump (DHCP/IP/DNS) first so a 20s campus visit is not lost
# behind slow pings.

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=C

LOGDIR="${HOME}/Library/Logs/nju-netmon"
STATEDIR="/tmp/nju-netmon"
LOCKDIR="${STATEDIR}/lock"
LAST_FP="${STATEDIR}/fingerprint"
LAST_VERDICT="${STATEDIR}/verdict"
LAST_SNAP="${STATEDIR}/last_snap"
PENDING="${STATEDIR}/pending"
JOURNAL="${LOGDIR}/events.log"
KEEP=40
WIFI_SERVICE="Wi-Fi"
UID_N="$(id -u)"

mkdir -p "$LOGDIR" "$STATEDIR"

now_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
now_id() { date '+%Y%m%d-%H%M%S'; }

logj() {
    printf '%s %s\n' "$(now_ts)" "$*" >>"$JOURNAL"
}

steal_stale_lock() {
    if [ -d "$LOCKDIR" ]; then
        local age
        age=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
        if [ "$age" -gt 20 ]; then
            rm -rf "$LOCKDIR"
        fi
    fi
}

dump() {
    local out="$1"
    shift
    {
        echo "\$ $*"
        "$@" 2>&1
        echo "exit:$?"
        echo
    } >>"$out"
}

dhcp_field() {
    local dev="$1" key="$2"
    ipconfig getpacket "$dev" 2>/dev/null | awk -v k="$key" '
        index($0, k) { sub(/.*: /, ""); print; exit }
    '
}

en0_ip() { ipconfig getifaddr en0 2>/dev/null || echo none; }
en0_router() { dhcp_field en0 'router (ip_mult)' || echo none; }
en0_dhcp_dns() { dhcp_field en0 'domain_name_server' || echo none; }
sys_dns() { networksetup -getdnsservers "$WIFI_SERVICE" 2>/dev/null | tr '\n' ',' || echo none; }

# Cheap: local syscalls only. Do not talk to Clash here.
fingerprint() {
    printf 'ip=%s|gw=%s|dhcpdns=%s|sysdns=%s|defif=%s' \
        "$(en0_ip)" \
        "$(en0_router)" \
        "$(en0_dhcp_dns)" \
        "$(sys_dns)" \
        "$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
}

clash_sock() {
    local s
    for s in /tmp/mihomo-party-"${UID_N}"-*.sock; do
        [ -S "$s" ] || continue
        if curl -sS -m 1 --unix-socket "$s" http://localhost/version >/dev/null 2>&1; then
            printf '%s' "$s"
            return 0
        fi
    done
    return 1
}

tun_flag() {
    local sock
    sock="$(clash_sock)" || { echo unknown; return; }
    curl -sS -m 1 --unix-socket "$sock" http://localhost/configs 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print('on' if d.get('tun',{}).get('enable') else 'off')" 2>/dev/null \
        || echo unknown
}

probe_http() {
    local url="$1"
    shift
    curl -sS -m 1 --interface en0 "$@" -D - -o /tmp/nju-netmon-body.$$ \
        -w 'http=%{http_code} ip=%{remote_ip} time=%{time_total} err=%{errormsg}\n' \
        "$url" 2>&1 || true
    echo "----- body -----"
    head -c 800 /tmp/nju-netmon-body.$$ 2>/dev/null
    echo
    rm -f /tmp/nju-netmon-body.$$
}

take_snapshot() {
    local reason="$1"
    local id dir
    id="$(now_id)"
    dir="${LOGDIR}/snap-${id}"
    mkdir -p "$dir"

    {
        echo "ts=$(now_ts)"
        echo "reason=$reason"
        echo "fingerprint=$(fingerprint)"
        echo "prev_fp=$(cat "$LAST_FP" 2>/dev/null || echo none)"
        echo "prev_verdict=$(cat "$LAST_VERDICT" 2>/dev/null || echo none)"
        echo "captive_tun_state=$(cat /tmp/nju-captive-tun.state 2>/dev/null || echo none)"
        echo "tun=$(tun_flag)"
    } >"$dir/00-meta.txt"

    # Phase 1: local-only, should finish in ~1s even with no network.
    dump "$dir/01-ifconfig.txt" ifconfig en0
    dump "$dir/01-ifconfig.txt" ifconfig utun1500
    dump "$dir/02-dhcp-en0.txt" ipconfig getpacket en0
    dump "$dir/03-summary-en0.txt" ipconfig getsummary en0
    dump "$dir/04-scutil-dns.txt" scutil --dns
    dump "$dir/05-sys-dns.txt" networksetup -getdnsservers "$WIFI_SERVICE"
    dump "$dir/05-sys-dns.txt" networksetup -getinfo "$WIFI_SERVICE"
    dump "$dir/06-resolv.txt" cat /etc/resolv.conf
    dump "$dir/07-resolver-nju.txt" cat /etc/resolver/nju.edu.cn
    dump "$dir/08-route-default.txt" route -n get default
    dump "$dir/16-nwi.txt" scutil --nwi

    logj "QUICK reason=$reason dir=snap-${id} ip=$(en0_ip) dhcpdns=$(en0_dhcp_dns) tun=$(tun_flag)"
    # Persist fingerprint before slow probes so a later run does not treat this as a new change.
    fingerprint >"$LAST_FP"

    # Phase 2: bounded probes. Run in parallel.
    local gw
    gw="$(en0_router | tr -d '{} ' | cut -d, -f1)"
    {
        echo "=== ping gw $gw ==="
        [ -n "$gw" ] && ping -c 1 -W 400 "$gw" 2>&1 || true
        echo "=== ping 210.28.129.251 ==="
        ping -c 1 -W 400 210.28.129.251 2>&1 || true
        echo "=== ping 219.219.115.44 ==="
        ping -c 1 -W 400 219.219.115.44 2>&1 || true
        echo "=== nc 210.28.129.251:53 ==="
        nc -G 1 -z 210.28.129.251 53 2>&1 || true
        echo "=== nc 219.219.115.44:80 ==="
        nc -G 1 -z 219.219.115.44 80 2>&1 || true
        echo "=== nc 219.219.115.44:443 ==="
        nc -G 1 -z 219.219.115.44 443 2>&1 || true
    } >"$dir/11-liveness.txt" &
    local p1=$!

    {
        echo "=== dscacheutil p.nju.edu.cn ==="
        dscacheutil -q host -a name p.nju.edu.cn 2>&1 || true
        echo "=== nslookup p.nju.edu.cn ==="
        nslookup -timeout=1 p.nju.edu.cn 2>&1 || true
        echo "=== nslookup @210.28.129.251 ==="
        nslookup -timeout=1 p.nju.edu.cn 210.28.129.251 2>&1 || true
        echo "=== nslookup @dhcp-dns ==="
        ddns="$(en0_dhcp_dns | tr -d '{}' | awk '{print $1}')"
        if [ -n "$ddns" ] && [ "$ddns" != "none" ]; then
            nslookup -timeout=1 p.nju.edu.cn "$ddns" 2>&1 || true
        fi
    } >"$dir/12-dns.txt" &
    local p2=$!

    {
        echo "=== http://p.nju.edu.cn/ via en0 ==="
        probe_http "http://p.nju.edu.cn/"
        echo "=== https://p.nju.edu.cn/ via en0 ==="
        probe_http "https://p.nju.edu.cn/" -k
        echo "=== http://219.219.115.44/ Host p.nju.edu.cn ==="
        probe_http "http://219.219.115.44/" -H "Host: p.nju.edu.cn"
        echo "=== http://captive.apple.com/hotspot-detect.html via en0 ==="
        probe_http "http://captive.apple.com/hotspot-detect.html"
    } >"$dir/13-probes.txt" &
    local p3=$!

    {
        echo "=== clash sock ==="
        clash_sock || echo none
        echo "=== tun ==="
        tun_flag
        sock="$(clash_sock || true)"
        if [ -n "${sock:-}" ]; then
            curl -sS -m 1 --unix-socket "$sock" http://localhost/configs 2>/dev/null \
                | python3 -c "
import sys,json
d=json.load(sys.stdin)
t=d.get('tun',{})
print('tun.enable', t.get('enable'))
print('tun.auto-detect-interface', t.get('auto-detect-interface'))
print('tun.dns-hijack', t.get('dns-hijack'))
print('tun.route-exclude-address', t.get('route-exclude-address'))
" 2>/dev/null || true
        fi
        echo "=== captive-tun.log tail ==="
        tail -20 "${HOME}/Library/Logs/nju-captive-tun.log" 2>/dev/null || echo none
        echo "=== core grep ==="
        clog="${HOME}/Library/Application Support/mihomo-party/logs/core-$(date +%Y-%m-%d).log"
        if [ -f "$clog" ]; then
            grep -E 'p\.nju|captive|Auto detect interface|interface not found|default interface changed' "$clog" | tail -40
        fi
    } >"$dir/14-clash.txt" &
    local p4=$!

    ( sleep 6; kill "$p1" "$p2" "$p3" "$p4" 2>/dev/null || true ) &
    wait "$p1" "$p2" "$p3" "$p4" || true

    local verdict="FAIL"
    if grep -q '并非校内地址' "$dir/13-probes.txt" 2>/dev/null; then
        verdict="FAIL-NOT-CAMPUS-IP"
    elif grep -q '<TITLE>Success</TITLE>' "$dir/13-probes.txt" 2>/dev/null \
        && grep -q 'http=200' "$dir/13-probes.txt" 2>/dev/null; then
        verdict="OK"
    elif ! grep -q 'inet ' "$dir/01-ifconfig.txt" 2>/dev/null; then
        verdict="FAIL-NO-IP"
    fi
    echo "$verdict" >"$dir/VERDICT"
    echo "$verdict" >"$LAST_VERDICT"
    echo "$dir" >"$LAST_SNAP"
    ln -sfn "$dir" "${LOGDIR}/latest"

    {
        echo "id=$id verdict=$verdict reason=$reason"
        echo "ip=$(en0_ip) gw=$(en0_router) dhcpdns=$(en0_dhcp_dns)"
        echo "sysdns=$(sys_dns) tun=$(tun_flag)"
        echo "dir=$dir"
    } >"$dir/SUMMARY.txt"

    logj "SNAP $verdict reason=$reason dir=snap-${id} ip=$(en0_ip) dhcpdns=$(en0_dhcp_dns) tun=$(tun_flag)"

    ls -1dt "$LOGDIR"/snap-* 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
        rm -rf "$old"
    done
}

steal_stale_lock
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    fingerprint >"$PENDING"
    exit 0
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null || true' EXIT

run_once() {
    local reason="$1"
    local fp
    fp="$(fingerprint)"
    take_snapshot "$reason"
    printf '%s\n' "$fp" >"$LAST_FP"
}

fp="$(fingerprint)"
prev="$(cat "$LAST_FP" 2>/dev/null || echo "")"

if [ -f "$PENDING" ]; then
    pending="$(cat "$PENDING")"
    rm -f "$PENDING"
    if [ "$pending" != "$prev" ]; then
        run_once "queued-change"
        fp="$(fingerprint)"
        prev="$(cat "$LAST_FP" 2>/dev/null || echo "")"
    fi
fi

if [ "$fp" != "$prev" ]; then
    run_once "change"
    exit 0
fi

exit 0
