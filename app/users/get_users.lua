local cjson = require("cjson.safe")
local log = require("resty.log")
local conf = require("conf")

local json_encode = cjson.encode 

local users = conf.users

local _M = {}

function _M.content()
	local res = users:get("/hello")
	return res
end

return _M

