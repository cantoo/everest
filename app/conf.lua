local location = require("resty.location")
local utils = require("resty.utils")

-- get local interface
local if_addr = utils.get_if_addr("eth0")
local server_port = 80

local _M = {
	registry = require("resty.registry.etcd"),
	balancer = require("resty.lb.wrr"),

	users = location.new("/_rpc_users_"),
}

return _M