local location = require("resty.location")

local _M = {
	users = location.new("/_rpc_/users_service"),
}

return _M
