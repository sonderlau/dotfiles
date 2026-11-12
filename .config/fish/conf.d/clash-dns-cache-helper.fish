function clash-dns-flush --description '刷新 Clash DNS 缓存'
    /usr/bin/python3 "$HOME/Library/Application Support/mihomo-party/dns-cache-helper/dns_cache_helper.py" --flush
end
