local location = require("resty.location")
local etcd = require("resty.registry.etcd")
local wrr = require("resty.lb.wrr")

local server_port = 8888

local _M = {
	-- 注册中心
	registry = etcd.new({
		name = "app",
		version = 1,
		ifa = "eno16777736",
		port = server_port,
	}),

	-- 负载均衡
	lb = wrr.new(),

	-- rpc clients
	users = location.new("/_rpc_app_", server_port)
}

function _M.init_worker()
	_M.registry:init_worker()
end

return _M
