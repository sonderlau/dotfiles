# 系统 DNS（路由器/校园解析器）对 *.x.ai 会间歇返回被污染的地址，
# CLI 直连这些地址会卡死，OIDC 刷新超时后就显示未登录、模型列表退回内置旧值。
# 走本地 HTTP 代理后由 Clash 按域名解析，问题消失。
function grok --description 'grok CLI，强制走本地 Clash HTTP 代理'
    HTTPS_PROXY=http://127.0.0.1:7890 HTTP_PROXY=http://127.0.0.1:7890 NO_PROXY=localhost,127.0.0.1 ~/.local/bin/grok $argv
end
