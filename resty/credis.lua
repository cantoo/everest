local redis = require("resty.redis")
local cjson = require("cjson.safe")

local _M = {}

local mt = { __index = _M }

function _M:new(conf)
    if not conf or not conf.host or not conf.password then
        error("host and password required")
    end

    local timeout = conf.timeout or 1000
    local port = conf.port or 6379
    local pool_size = conf.pool_size or 20
    local max_idle_timeout = conf.max_idle_timeout or 60000

    return setmetatable({
        timeout = timeout,
        port = port,
        pool_size = pool_size,
        max_idle_timeout = max_idle_timeout,
        host = conf.host,
        password = conf.password}, mt)
end

function _M:connect()
    local red = redis:new()
    if not red then
        return nil, "failed to instance redis"
    end

    red:set_timeout(self.timeout)
    local res, err = red:connect(self.host, self.port)
    if not res then
        return nil, "failed to connect: " .. err
    end

    res, err = red:get_reused_times()
    if not res then
        return nil, "failed to get reused times: " .. err
    end

    if res == 0 then
        res, err = red:auth(self.password)
        if not res then
            return nil, "failed to auth: " .. err
        end
    end

    return red
end

function _M:set_keepalive(red)
    red:set_keepalive(self.max_idle_timeout, self.pool_size)
end

function _M:array_to_hash(array)
    return redis:array_to_hash(array)
end

function _M:do_cmd(cmd, ...)
    local args = { ... }
    local red, err = self:connect()
    if not red then
        return nil, err
    end

    local res
    local func = redis[cmd]
    res, err = func(red, unpack(args))
    if not res then
        ngx.log(ngx.ERR, "failed to execute: " .. err, ",cmd=", cmd)
        return nil, err
    end

    ngx.log(ngx.DEBUG, "cmd=", cmd, ",args=", cjson.encode(args), ",res=", cjson.encode(res))
    self:set_keepalive(red)
    return res
end

function _M:pipeline(cmds)
    local red, err = self:connect()
    if not red then
        return nil, err
    end

    red:init_pipeline()
    for _, cmd in ipairs(cmds) do
        local func = redis[cmd[1]]
        local args = {}
        table.move(cmd, 2, #cmd, 1, args)
        func(red, unpack(args))
    end

    local results
    results, err = red:commit_pipeline()
    if not results then
        return nil, "failed to commit pipeline: " .. err
    end

    -- for i, res in ipairs(results) do
    --     if type(res) == "table" then
    --         if res[1] == false then
    --             ngx.log(ngx.ERR, "failed to run command ", i, ": ", res[2])
    --         else
    --             -- process the table value
    --         end
    --     else
    --         -- process the scalar value
    --     end
    -- end
    
    ngx.log(ngx.DEBUG, "cmds=", cmds, ",results=", cjson.encode(results))
    self:set_keepalive(red)
    return results
end


return _M



