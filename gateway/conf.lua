local etcd = require("resty.registry.etcd")
local wrr = require("resty.lb.wrr")

local _M = {}

-- 注册中心
_M.registry = etcd.new()


-- 负载均衡
_M.lb = wrr.new()


-- 插件
_M.phase_plugins = {
	["access"] = { 
		require("plugins.registry"), 
		require("plugins.auth"),
	}
}

return _M