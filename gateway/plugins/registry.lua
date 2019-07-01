local conf = require("conf")

local ngx_var = ngx.var
local ngx_exit = ngx.exit
local registry = conf.registry

local _M = {}

function _M.access() 
	-- must set $app var as upstream service name
	-- prepare upstreams
	local ok, err = registry.prepare(ngx_var.application)
	if not ok then
		ngx_exit(ngx.HTTP_BAD_GATEWAY)
		return false, err
	end

	return true, nil
end

return _M
