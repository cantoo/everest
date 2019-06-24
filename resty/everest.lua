local conf = require("conf")
local restful = require("resty.restful")

local registry = conf.registry
local balancer = conf.balancer
local table_concat = table.concat
local ngx_var = ngx.var
local ngx_req_set_uri = ngx.req.set_uri

local _M = {}

function _M.init()
end

function _M.init_worker()
	if registry then
		registry.init_worker()
	end
end

-- used as gateway access phase
function _M.access()
	if registry then
		-- must set $app var as upstream service name
		-- prepare upstreams
		local err = registry.prepare(ngx_var.application)
		if err ~= nil then
			return ngx.exit(ngx.HTTP_BAD_GATEWAY)
		end
	end

	local auth = conf.auth 
	if auth then
		return auth.auth()
	end
end

-- used as app service rpc rewrite phase
function _M.rewrite()
	if not registry then
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end

	-- prepare upstreams
	local err = registry.prepare(ngx.var[1])
	if err ~= nil then
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end
	
	return ngx_req_set_uri(ngx.var[2])
end

-- used as services except gateway content phase
function _M.content()
	local res1 = ngx_var[1]
	local res1_sub = ngx.re.match(res1, "^.*_([a-z]+)$")
	res1_sub = res1_sub and res1_sub[1] or res1

	local echo_request_method = string.lower(ngx_var.echo_request_method)
	local method_resources_file = table_concat({echo_request_method, res1, ngx_var[3], ngx_var[5]}, "_")

	local ok, handler = pcall(require, table_concat({res1_sub, method_resources_file}, "."))
	if not ok then
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end

	return restful.say(handler.content())
end

-- used as rpc load balance
function _M.balancer()
end

-- used as rpc qos statistic
function _M.log()
end

return _M
