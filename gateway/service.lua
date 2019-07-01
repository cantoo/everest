local etcd = require("resty.registry.etcd")
local wrr = require("resty.lb.wrr")

local ngx_var = ngx.var

local _M = {
	-- 注册中心
	registry = etcd.new(),

	-- 负载均衡
	lb = wrr.new(),
}

local function _registry_access()
	-- must set $app var as upstream service name
	-- prepare upstreams
	local ok = _M.registry:prepare(ngx_var.application)
	if not ok then
		return ngx.HTTP_BAD_GATEWAY
	end

	return nil
end

function _M.access()
	local status = _registry_access()
	if status then
		return status
	end
end


return _M
