--[[
author: jie123108@163.com
date: 20150901
]]

local _M = {}
local http = require "resty.http"   -- https://github.com/pintsized/lua-resty-http

function _M.trim (s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- delimiter 应该是单个字符。如果是多个字符，表示以其中任意一个字符做分割。
function _M.split(s, delimiter)
    local result = {};
    for match in string.gmatch(s, "[^"..delimiter.."]+") do
        table.insert(result, match);
    end
    return result;
end


function _M.new_headers()
    local t = {}
    local lt = {}
    local _mt = {
        __index = function(t, k)
            return rawget(lt, string.lower(k))
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            rawset(lt, string.lower(k), v)
        end,
     }
    return setmetatable(t, _mt)
end

function readresolv(filename)
    local rfile=io.open(filename, "r") --读取文件(r读取)
    if not rfile then
        return nil
    end
    local resolvs = {}
    for str in rfile:lines() do     --一行一行的读取
        str = _M.trim(str)
        ngx.log(ngx.INFO, "str:", str)
        local len = string.len(str)
       if len > 10 and string.sub(str,1,1) ~= '#' then
            local sarr = _M.split(str, ' \t')
            if table.getn(sarr) == 2 and sarr[1] == "nameserver" then
                --print("nameserver:", sarr[2])
                table.insert(resolvs, sarr[2])
            end
       end
    end
    rfile:close()
    return resolvs
end

_M.nameservers = nil
_M.strnameservers = nil

function _M.dns_init()
    --ngx.log(nxg.INFO, "############# dns_init ##############")
    local resolv_file = "/etc/resolv.conf"
       
    ngx.log(ngx.INFO, "init dns from resolv_file:", resolv_file)
    local dns_svr = {"8.8.8.8"}
    local resolvs = readresolv(resolv_file)
    if resolvs then
        dns_svr = resolvs
    end

    if type(dns_svr) == 'table' then
        for i,nameserver in ipairs(dns_svr) do
            ngx.log(ngx.INFO, "nameserver: ", nameserver)
        end
    else
        ngx.log(ngx.INFO, "nameserver: ", dns_svr)
    end

    _M.nameservers = {}
    _M.strnameservers = {}

    if dns_svr then
        local dns_svrs = nil
        if type(dns_svr) == 'table' then
            dns_svrs = dns_svr
        else
            dns_svrs = {dns_svr}
        end
        for i,dns_svr in ipairs(dns_svrs) do
            local dnsarr = _M.split(dns_svr, ':')
            if table.getn(dnsarr) == 2 then
                local dns_host = dnsarr[1]
                local dns_port = tonumber(dnsarr[2]) or 53
                table.insert(_M.nameservers, {dns_host, dns_port})
            else
                table.insert(_M.nameservers, dns_svr)
            end
            table.insert(_M.strnameservers, dns_svr)
            --ngx.log(ngx.INFO, "DNS:", dns_svr)
        end        
    else
        table.insert(_M.nameservers, "8.8.8.8")
        table.insert(_M.nameservers, {"8.8.4.4", 53})
        table.insert(_M.strnameservers, "8.8.8.8")
        table.insert(_M.strnameservers, "8.8.8.4:53")
    end

end

function _M.is_ip(strip)
    if strip == nil or strip == "" then
        return false
    end
    return string.match(strip, "^%d+.%d+.%d+.%d+") ~= nil
end

function _M.dns_query(domain)
    local dns_key = "dns:" .. domain 
    local cache = ngx.shared.cache
    if cache then
        local v = cache:get(dns_key)
        if v then
            ngx.log(ngx.INFO, "resolver [", domain, "] from cache! address:", v)
            return v
        end
    end

    local resolver = require "resty.dns.resolver"
    
    local answers = nil
    local err = nil
    local dns_query_timeout = dns_query_timeout or 5000
    --依次从多个DNS服务器上查询域名。
    for i, nameserver in ipairs(_M.nameservers) do
        local strnameserver = _M.strnameservers[i]

        local cur_nameservers = {nameserver}
        ngx.log(ngx.INFO, "######### resolve [",domain,"] from:[", strnameserver, "]")

        local r, err = resolver:new{
            nameservers = cur_nameservers,
            retrans = 3,  -- 5 retransmissions on receive timeout
            timeout = dns_query_timeout,  -- 2 sec
        }
       
        if not r then
            ngx.log(ngx.ERR, "failed to instantiate the dns resolver: ", err)
        else 

            r:set_timeout(dns_query_timeout)
            answers, err= r:query(domain)
            if answers and not answers.errcode and table.getn(answers) > 0 then
                -- 成功了。
                ngx.log(ngx.INFO, "........... answers:", table.getn(answers))
                break 
            end

            if answers then
                if answers.errcode then
                    ngx.log(ngx.ERR, "dns server returned error code: ", answers.errcode,":", answers.errstr)
                elseif table.getn(answers)==0 then
                    ngx.log(ngx.ERR, "dns server returned zero item from: ", strnameserver)
                end
            else
                ngx.log(ngx.ERR, "failed to query the DNS server: ", err)
            end           
        end
    end
    if not answers then
        return nil
    end

    local addrs = {}

    for i, ans in ipairs(answers) do
        ngx.log(ngx.INFO, "dns_resp:", ans.name, " ", ans.address or ans.cname,
                " type:", ans.type, " class:", ans.class,
                " ttl:", ans.ttl)
        if ans.address then
            table.insert(addrs, ans)
        end
    end

    local n = table.getn(addrs)
    if n == 0 then
        ngx.log(ngx.ERR, string.format("no valid ip in the dns response!"))
        return nil
    end
    n = math.random(n)
    local addr = addrs[n]
    if not _M.is_ip(addr.address) then
        ngx.log(ngx.ERR, string.format("invalid ip [%s] from the dns response!", addr.address))
        return nil
    end
    
    ngx.log(ngx.INFO, "dns query:{domain:",domain, ", address:", addr.address, ", ttl:", addr.ttl, "}")

    if addr.ttl == 0 then
        addr.ttl = 60*5
    end
    if cache then
        ngx.log(ngx.INFO, "set dns cache(", dns_key, ",", addr.address, ",", addr.ttl, ")...")
        cache:set(dns_key, addr.address, addr.ttl)
    end

    return addr.address
end

-- return uri, args
function _M.short_url_parse(url)
    if url == nil or url == "" then
        return nil
    end

    local uri, args = nil

    local uri_end, args_begin = nil, nil
    local x = string.find(url, "?")
    if x then
        uri = string.sub(url, 1, x-1)
        args = string.sub(url, x+1)
    else
        uri = url
    end

    return uri, args
end

-- return schema, host, port, uri, args
function _M.full_url_parse(url)
    if url == nil or url == "" then
        return nil
    end

    local host_start = 1
    local host_and_port = nil
    local schema, host, port, uri, args = nil

    if string.sub(url, 1, 7) == "http://" then
        schema = "http"
        host_start = 8
    elseif string.sub(url, 1, 8) == "https://" then
        schema = "https"
        host_start = 9
    end
    local uri_begin = string.find(url, "/", host_start)
    if uri_begin then
        host_and_port = string.sub(url, host_start, uri_begin-1)
        uri = string.sub(url, uri_begin)
        uri, args = _M.short_url_parse(uri)
    else -- uri_begin is nil
        host_and_port = string.sub(url, host_start)
    end
    if host_and_port then
        local x = string.find(host_and_port, ":")
        --print ("xxx:", host_and_port, " ", x)
        if x then -- 包含端口。
            host = string.sub(host_and_port, 1, x-1)
            port = tonumber(string.sub(host_and_port, x+1))
        else
            host = host_and_port
        end
    end

    return schema, host, port, uri, args
end

function _M.get_resolver_url(url)
    if url == nil or url == "" then
        return nil
    end

    local xurl = url
    if string.sub(url, 1, 7) == "http://" then
        xurl = string.sub(url, 8)
    end

    -- print(xurl)
    local m = string.match(xurl, "^%d+.%d+.%d+.%d+")
    if m then -- 直接使用IP地址的。
        return url,nil
    else -- 使用域名的。
        
        local index = string.find(xurl, "[:/]", 1)        
        local host = xurl
        local rest = nil
        if index then
            host = string.sub(xurl, 1, index-1)
            rest = string.sub(xurl, index)
        end
        
        -- 解析域名。。
        local addr = _M.dns_query(host)
        if addr == nil then
            ngx.log(ngx.ERR, "dns_query(", host, ") failed!")
            return nil, "dns query failed for host '" .. host .. "' "
        end

        local addr_full = "http://" .. addr
        if rest then
            addr_full = addr_full .. rest
        end
        return addr_full, host
    end
end

function _M.headerstr(headers)
    if headers == nil or headers == {} then
        return ""
    end
    local lines = {}
    for k, v in pairs(headers) do
        if type(v) == 'table' then
            v = table.concat(v, ',')
        end
        if k ~= "User-Agent" then
            table.insert(lines, "-H'" .. k .. ": " .. v .. "'");
        end
    end
    return table.concat(lines, " ")
end

local function http_req(method, url, body, myheaders, timeout)
    local uri, host = _M.get_resolver_url(url)
    if uri == nil then
        ngx.log(ngx.ERR, "resolver [", url, "] failed! ")
        return nil, host, url
    end

    if myheaders == nil then myheaders = _M.new_headers() end

    if host ~= nil and myheaders["Host"] == nil then
        myheaders["Host"] = host
    end

    local timeout_str = "-"
    if timeout then
        timeout_str = tostring(timeout)
    end
    local req_debug = ""
    if method == "PUT" or method == "POST" then
        local debug_body = nil
        local content_type = myheaders["Content-Type"]
        if content_type == nil or _M.startswith(content_type, "text") then 
            if string.len(body) < 1024 then
                debug_body = body
            else
                debug_body = string.sub(body, 1, 1024)
            end
        else 
            debug_body = "[[not text body: " .. tostring(content_type) .. "]]"
        end
        req_debug = "curl -v -X " .. method .. " " .. _M.headerstr(myheaders) .. " '" .. uri .. "' -d '" .. debug_body .. "' -o /dev/null"
    else
        body = nil
        req_debug = "curl -v -X " .. method .. " " .. _M.headerstr(myheaders) .. " '" .. uri .. "' -o /dev/null"
    end
    ngx.log(ngx.INFO, method, " REQUEST [ ", req_debug, " ] timeout:", timeout_str)
    local httpc = http.new()
    if timeout then
        httpc:set_timeout(timeout)
    end
    local begin = ngx.now()
    local res, err = httpc:request_uri(uri, {method = method, headers = myheaders, body=body})
    local cost = ngx.now()-begin
    if not res then
        ngx.log(ngx.ERR, "FAIL REQUEST [ ",req_debug, " ] err:", err, ", cost:", cost)
    elseif res.status >= 400 then
        ngx.log(ngx.ERR, "FAIL REQUEST [ ",req_debug, " ] status:", res.status, ", const:", cost)
    else 
        ngx.log(ngx.INFO, "REQUEST [ ",req_debug, " ] status:", res.status, ", const:", cost)
    end
    return res, err, req_debug
end

function _M.http_head(uri, myheaders, timeout)
    return http_req("HEAD", uri, nil, myheaders, timeout)
end

function _M.http_get(uri, myheaders, timeout)
    return http_req("GET", uri, nil, myheaders, timeout)
end

function _M.http_del(uri, myheaders, timeout)
    return http_req("DELETE", uri, nil, myheaders, timeout)
end

function _M.http_post(uri, body, myheaders, timeout)
    return http_req("POST", uri, body, myheaders, timeout)
end

function _M.http_put(uri,  body, myheaders, timeout)
    return http_req("PUT", uri, body, myheaders, timeout)
end

-- 尝试从/etc/resolv.conf读取dns配置(如果有配置)。
_M.dns_init()

return _M