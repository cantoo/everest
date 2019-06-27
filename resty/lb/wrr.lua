local ngx_balancer = require("ngx.balancer")
local log = require("resty.log")

local _M = {}
local mt = { __index = _M }

function _M.new()
	return setmetatable({}, mt)
end

function _M:balancer() 
	local ok, err = ngx_balancer.set_current_peer("127.0.0.1", 6666)
    if not ok then
        log.error("failed to set the current peer: ", err)
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
end

return _M

