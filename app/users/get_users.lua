local conf = require("conf")
local users = conf.users

local _M = {}

function _M.content()
	return users.get("/hello")
end

return _M

