local conf = require("conf")
local restful = require("resty.restful")

local registry = conf.registry
local table_concat = table.concat
local ngx_var = ngx.var

local _M = {}

function _M.init()
end

function _M.init_worker()
	registry.init_worker(conf.service_name)
end

-- used as gateway access phase
function _M.gateway_access()
	-- must set $service_name var as upstream service name
	-- prepare upstreams
	local ok = registry.prepare(ngx_var.service_name)
	if not ok then
		return ngx.exit(ngx.HTTP_BAD_GATEWAY)
	end

	local auth = conf.auth 
	if auth then
		return auth.auth()
	end
end

-- used as app service rpc rewrite phase
function _M.rpc_access()
	-- must set $service_name var as upstream service name
	-- prepare upstreams
	local ok = registry.prepare(ngx_var.service_name)
	if not ok then
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end
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

	return restful.say(handler.handle())
end

return _M
