local location = require("resty.location")
local etcd = require("resty.registry.etcd")
local wrr = require("resty.lb.wrr")

local server_port = 80

local _M = {
	registry = etcd.new({
		name = "app",
		version = 1,
		ifa = "eno16777736",
		port = server_port,
	}),

	lb = wrr.new(),
	users = location.new("/_rpc_app_", server_port),
}

return _M