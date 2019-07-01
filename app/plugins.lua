local conf = require("conf")

local registry = conf.registry

local _M = {
	["init_worker"] = { 
		registry,
	}
}

return _M
