local http = require("resty.http")
local cjson = require("cjson.safe")

local new_http = http.new
local new_tab = table.new
local table_concat = table.concat
local table_insert = table.insert
local json_encode = cjson.encode
local json_decode = cjson.decode

local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    conf = conf or {} 

    local host, port
    if type(conf.host) == "string" then
        local match = ngx.re.match("(\\d+(?:\\.\\d+){3}):(\\d+)")
        if match and #match >= 2 then
            host = match[1]
            port = match[2]
        end
    else
        host = "127.0.0.1"
        port = 2379
    end 
    
    local prefix = conf.prefix or "v3beta"
    local timeout = conf.timeout or 5

    return setmetatable({
        host = host,
        port = port,
        prefix = prefix,
        timeout = timeout
    }, mt)
end

local function _request_uri(etcdcli, cmd, body)
    local httpc, err = new_http()
    if not httpc then
        return nil, err
    end

    httpc:set_timeout(etcdcli.timeout * 1000)

    local res
    res, err = httpc:request_uri(table_concat("http://", etcdcli.host, ":", etcdcli.port, "/", etcdcli.prefix, cmd), {
        method = "POST",    
        body = json_encode(body)
    })

    if not res then
        -- todo add err log
        return nil, err
    end

    -- todo debug res
    if res.status >= 300 then
        return nil, "etcdcli response status " .. res.status
    end

    return json_decode(res.body) or {}, nil
end

function _M:range(key, range_end)
    local body, err = _request_uri(self, "/kv/range", {
        key = key, 
        range_end = range_end,
    })

    if not body then
        return nil, err
    end

    return body.kvs, nil
end

function _M:grant(ttl)
    local body, err = _request_uri(self, "/lease/grant", {
        TTL = ttl, 
    })

    if not body then
        return nil, err
    end

    return body.ID, nil
end

function _M:put(key, value, lease)
    local body, err = _request_uri(self, "/kv/put", {
        key = key,
        value = value,
        lease = lease, 
    })

    if not body then
        return nil, err
    end 

    return true, nil
end

function _M:keepalive(lease)
    local body, err = _request_uri(self, "/lease/keepalive", {
        lease = lease, 
    })

    if not body then
        return nil, err
    end 

    return true, nil
end

function _M:revoke(lease)
end

function _M:watch(key, range_end)
    local httpc, err = new_http()
    if not httpc then
        return nil, nil, err
    end

    httpc:set_timeout(self.timeout * 1000)

    local ok
    ok, err = httpc:connect(self.host, self.port)
    if not ok then
        return nil, nil, err
    end

    local res, err = httpc:request({
        path = "/watch",
        body = json_decode({
            create_request = {
                key = key,
                range_end = range_end,
            }
        })
    })

    if not res then
        -- todo error log
        return nil, nil, err
    end

    -- todo debug res
    if res.status >= 300 then
        return nil, "etcdcli response status " .. res.status
    end

    local close = httpc.close
    return res.body_reader, close, nil
end

return _M


