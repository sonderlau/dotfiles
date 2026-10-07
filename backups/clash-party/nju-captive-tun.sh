#!/bin/bash
# Pause Clash TUN on NJU-WLAN until the network is online.
# Idle path: DHCP packet + route lookup only. HTTP probes run once per
# new campus join, then only while paused (waiting for auth).

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LOG="${HOME}/Library/Logs/nju-captive-tun.log"
STATE="/tmp/nju-captive-tun.state"
LAST_DHCP="/tmp/nju-captive-tun.last_dhcp"
WIFI_SERVICE="Wi-Fi"

log() {
    echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $*" >>"$LOG"
}

clash_sock() {
    local s
    for s in /tmp/mihomo-party-"$(id -u)"-*.sock; do
        [ -S "$s" ] || continue
        if curl -sS -m 1 --unix-socket "$s" http://localhost/version >/dev/null 2>&1; then
            echo "$s"
            return 0
        fi
    done
    return 1
}

tun_set() {
    local enable="$1" sock
    sock="$(clash_sock)" || return 1
    curl -sS -m 3 --unix-socket "$sock" -X PATCH http://localhost/configs \
        -H 'Content-Type: application/json' \
        -d "{\"tun\":{\"enable\":${enable}}}" >/dev/null
}

dns_dhcp() {
    networksetup -setdnsservers "$WIFI_SERVICE" Empty >/dev/null 2>&1
    dscacheutil -flushcache >/dev/null 2>&1 || true
}

dns_clash() {
    networksetup -setdnsservers "$WIFI_SERVICE" 198.19.0.1 223.5.5.5 >/dev/null 2>&1
}

campus_dhcp_id() {
    ipconfig getpacket en0 2>/dev/null | awk '
        /domain_name_server/ { dns=$0 }
        /yiaddr/ { ip=$0 }
        END { print ip "|" dns }
    '
}

is_campus_dhcp() {
    ipconfig getpacket en0 2>/dev/null | grep -qE '10\.28\.253\.4|10\.12\.253\.4|210\.28\.129\.25'
}

has_default_route() {
    route -n get default >/dev/null 2>&1
}

http_code() {
    curl -sS -m 2 "$@" -o /dev/null -w '%{http_code}' 2>/dev/null || echo 000
}

is_online() {
    local body code
    body="$(curl -sS -m 2 --interface en0 http://captive.apple.com/hotspot-detect.html 2>/dev/null || true)"
    printf '%s' "$body" | grep -q Success && return 0
    code="$(http_code --interface en0 http://connect.rom.miui.com/generate_204)"
    if [ "$code" = "204" ] || [ "$code" = "200" ]; then
        return 0
    fi
    code="$(http_code http://www.baidu.com/)"
    if [ "$code" = "200" ]; then
        return 0
    fi
    return 1
}

pause_for_portal() {
    dns_dhcp
    tun_set false || true
    echo paused >"$STATE"
    log "pause TUN+DHCP DNS ip=$(ipconfig getifaddr en0 2>/dev/null)"
}

resume_clash() {
    tun_set true || true
    sleep 1
    dns_clash
    rm -f "$STATE"
    log "resume TUN+Clash DNS"
}

mkdir -p "$(dirname "$LOG")"

if ! is_campus_dhcp; then
    if [ -f "$STATE" ]; then
        resume_clash
    fi
    exit 0
fi

# Campus. Already paused: only then poll for auth.
if [ -f "$STATE" ]; then
    if is_online; then
        resume_clash
    fi
    exit 0
fi

dhcp_id="$(campus_dhcp_id)"
prev_dhcp="$(cat "$LAST_DHCP" 2>/dev/null || echo "")"
printf '%s\n' "$dhcp_id" >"$LAST_DHCP"

# No default route yet: TUN is eating the route. Pause without HTTP.
if ! has_default_route; then
    pause_for_portal
    exit 0
fi

# New campus join (DHCP identity changed): one online probe.
if [ "$dhcp_id" != "$prev_dhcp" ]; then
    if ! is_online; then
        pause_for_portal
    fi
fi

exit 0
