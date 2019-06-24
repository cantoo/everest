

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

end

function _M:grant(ttl)
end

function _M:put(key, value, lease)
end

function _M:keepalive(lease)
end

function _M:watch(key, range_end)
end

return _M


