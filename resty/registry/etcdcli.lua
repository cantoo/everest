local http = require("resty.http")
local cjson = require("cjson.safe")
local log = require("resty.log")

local new_http = http.new
local table_concat = table.concat
local json_encode = cjson.encode
local json_decode = cjson.decode

local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    conf = conf or {} 
    local host = conf.host or "127.0.0.1"
    local port = conf.port or 2379
    local prefix = conf.prefix or "/v3beta"
    local timeout = conf.timeout or 5
    local watch_timeout = conf.watch_timeout or 10

    return setmetatable({
        host = host,
        port = port,
        prefix = prefix,
        timeout = timeout,
        watch_timeout = watch_timeout,
    }, mt)
end

local function _request_uri(etcdcli, cmd, body)
    local httpc, err = new_http()
    if not httpc then
        return nil, err
    end

    httpc:set_timeout(etcdcli.timeout * 1000)
    local request_body = json_encode(body)

    local res
    local uri = table_concat({"http://", etcdcli.host, ":", etcdcli.port, etcdcli.prefix, cmd})
    res, err = httpc:request_uri(uri, {
        method = "POST",    
        body = request_body,
    })

    if not res then
        log.error(err)
        return nil, err
    end

    log.debug("cmd=", cmd, ",request body=", request_body, ",response status=", res.status, ",response body=", res.body)
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
        ID = lease, 
    })

    if not body then
        return nil, err
    end 

    return true, nil
end

function _M:revoke(lease)
    local body, err = _request_uri(self, "/kv/lease/revoke", {
        ID = lease, 
    })

    if not body then
        return nil, err
    end 

    return true, nil
end

function _M:watch(key, range_end)
    local httpc, err = new_http()
    if not httpc then
        log.error(err)
        return nil, nil, err
    end

    httpc:set_timeouts(self.timeout * 1000, self.timeout * 1000, nil)

    local ok
    ok, err = httpc:connect(self.host, self.port)
    if not ok then
        log.error(err)
        return nil, nil, err
    end

    local res
    res, err = httpc:request({
        method = "POST",
        path = self.prefix .. "/watch",
        body = json_encode({
            create_request = {
                key = key,
                range_end = range_end,
            }
        }),
    })

    if not res then
        log.error(err)
        return nil, nil, err
    end

    log.debug("key=", key, ",range_end=", range_end, ",response status=", res.status, ",response body=", res.body)
    if res.status >= 300 then
        return nil, "etcdcli response status " .. res.status
    end

    return res.body_reader, httpc, nil
end

return _M


