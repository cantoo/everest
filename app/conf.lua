local location = require("resty.location")

-- get local interface
local server_port = 80

local _M = {
	registry = require("resty.registry.etcd"),
	balancer = require("resty.lb.wrr"),


	users = location.new("/_rpc_users_"),
}

return _M