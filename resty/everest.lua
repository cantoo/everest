local conf = require("conf")
local restful = require("resty.restful")
local log = require("resty.log")

local table_concat = table.concat
local ngx_var = ngx.var
local ngx_ctx = ngx.ctx
local ngx_req_set_uri = ngx.req.set_uri

local registry = conf.registry
local lb = conf.lb

local _M = {}

local function _run_plugins(phase)
    local ok, phase_plugins = pcall(require, "plugins")
    if not ok then
        return ok, phase_plugins
    end

    local plugins = phase_plugins[phase]
    if type(plugins) == "table" then
        for _, plugin in ipairs(plugins) do
            local err
            ok, err = plugin[phase]()
            if not ok then
                log.error(err)
                return false, err
            end
        end
    end

    return true, nil
end

function _M.init()
    return _run_plugins("init")
end

function _M.init_worker()
    return _run_plugins("init_worker")
end

function _M.set()
    local res1 = ngx_var[1]
    local res1_sub = ngx.re.match(res1, "^.*_([a-z]+)$")
    res1_sub = res1_sub and res1_sub[1] or res1

    local echo_request_method = string.lower(ngx_var.echo_request_method)
    local method_resources_file = table_concat({echo_request_method, res1, ngx_var[3], ngx_var[5]}, "_")

    local ok, handler = pcall(require, table_concat({res1_sub, method_resources_file}, "."))
    if not ok then
        log.error(handler)
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end

    ngx_ctx.handler = handler
end

-- used as app service rpc rewrite phase
function _M.rewrite()
    -- prepare upstreams
    local ok = registry:prepare(ngx.var[1])
    if not ok then
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
    
    return ngx_req_set_uri(ngx.var[2])
end

-- used as gateway access phase
function _M.access()
    local ok, err = _run_plugins("access")
    if not ok then
        return false, err
    end

    if ngx_ctx.handler and ngx_ctx.handler.access then
        return ngx_ctx.handler.access()
    end

    return true, nil
end

-- used as services except gateway content phase
function _M.content()
    return restful.say(ngx_ctx.handler.content())
end

-- used as rpc load balance
function _M.balancer()
    return lb.balancer()
end

-- used as rpc qos statistic
function _M.log()
    return lb.log()
end

return _M
