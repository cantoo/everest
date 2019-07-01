local service = require("service")

local users = service.users

local _M = {}

function _M.content()
	local res = users:get("/hello")
	return res
end

return _M

