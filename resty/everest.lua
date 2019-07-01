local service = require("service")
local restful = require("resty.restful")

local table_concat = table.concat
local ngx_var = ngx.var
local ngx_exit = ngx.exit
local ngx_req_set_uri = ngx.req.set_uri

local registry = service.registry
local lb = service.lb

local _M = {}

function _M.init()
    if service.init then
        return service.init()
    end
end

function _M.init_worker()
    if service.init_worker then
        return service.init_worker()
    end
end

function _M.set()
    local res1 = ngx_var[1]
    local res1_sub = ngx.re.match(res1, "^.*_([a-z]+)$")
    res1_sub = res1_sub and res1_sub[1] or res1

    local echo_request_method = string.lower(ngx_var.echo_request_method)
    local method_resources_file = table_concat({echo_request_method, res1, ngx_var[3], ngx_var[5]}, "_")

    return table_concat({res1_sub, method_resources_file}, ".")
end

-- used as app service rpc rewrite phase
function _M.rewrite()
    if not registry then
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end

    -- prepare upstreams
    local ok = registry:prepare(ngx.var[1])
    if not ok then
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
    
    return ngx_req_set_uri(ngx.var[2])
end

-- used as gateway access phase
function _M.access()
    if service.access then
        local status = service.access()
        if status then
            return ngx_exit(status)
        end
    end

    if ngx_var.handler then
        local handler = require(ngx_var.handler)
        if handler.access then
            local status = handler.access()
            if status then
                return ngx_exit(status)
            end
        end
    end
end

-- used as services except gateway content phase
function _M.content()
    local handler = require(ngx_var.handler)
    return restful.say(handler.content())
end

-- used as rpc load balance
function _M.balancer()
    return lb:balancer()
end

-- used as rpc qos statistic
function _M.log()
    return lb:log()
end

return _M
