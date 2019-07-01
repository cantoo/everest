local conf = require("conf")

local users = conf.users

local _M = {}

function _M.content()
	local res = users:get("/hello")
	return res
end

return _M

