local http = require("resty.http")
local cjson = require("cjson.safe")

local new_http = http.new
local new_tab = table.new
local table_concat = table.concat
local table_insert = table.insert
local json_encode = cjson.encode
local json_decode = cjson.decode
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    conf = conf or {} 
    local host = conf.host or "127.0.0.1:2379"
    local prefix = conf.prefix or "v3beta"
    local timeout = conf.timeout or 5

    return setmetatable({
        host = host,
        prefix = prefix,
        timeout = timeout
    }, mt)
end

function _M:range(key, range_end)
    local httpc = new_http()
    local res, err = httpc:request_uri(table_concat("http://", self.host, "/", self.prefix, "/kv/range"), {
        method = "POST",    
        body = json_encode({
            key = encode_base64(key), 
            range_end = encode_base_64(range_end),
        }),
    })

    if not res then
        -- todo add err log
        return nil, err
    end

    -- todo debug body
    local body = json_decode(res.body) or {}
    -- if type(body) == "table" and type(body.kvs) == "table" then
    --     for _, kv in ipairs(body.kvs) do 
    --         if type(kv) == "table" and type(kv.value) == "string" then    
    --             local addr = decode_json(decode_base64(kv.value))
    --             if type(addr) == "table" and type(addr.addr) == "string" then
    --                 table_insert(addrs, addr)
    --             end
    --         end
    --     end
    -- end

    -- if #addrs == 0 then 
    --     addrs = nil
    -- end

    return body.kvs, nil
end

function _M:grant(ttl)
    local httpc = new_http()
    local res, err = httpc:request_uri(table_concat("http://", self.host, "/", self.prefix, "/lease/grant"), {
        method = "POST",    
        body = json_encode({
            TTL = ttl, 
        }),
    })

    if not res then
        -- todo add err log
        return nil, err
    end

    -- todo debug body
    local body = json_decode(res.body) or {}
    return body.ID, nil
end

function _M:put(key, value, lease)
    local httpc = new_http()
    local res, err = httpc:request_uri(table_concat("http://", self.host, "/", self.prefix, "/kv/put"), {
        method = "POST",    
        body = json_encode({
            key = encode_base64(key),
            value = encode_base64(value),
            lease = lease, 
        }),
    })

    if not res then
        -- todo add err log
        return false, err
    end

    -- todo debug body
    return true, nil
end

function _M:keepalive(lease)
end

function _M:revoke(lease)
end

function _M:watch(key, range_end)
end

return _M


