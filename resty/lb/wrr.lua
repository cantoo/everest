local ngx_balancer = require("ngx.balancer")
local cjson = require("cjson.safe")
local log = require("resty.log")

local registry = ngx.shared.registry
local json_decode = cjson.decode

local _M = {}
local mt = { __index = _M }

function _M.new()
	return setmetatable({}, mt)
end

function _M:balancer() 
	local service_name = ngx.ctx.service_name
	if not service_name then
		log.error("balance service not found,name=", service_name)
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end

	local addrs = registry:get(service_name)
	log.debug(addrs)
	if addrs then
		addrs = json_decode(addrs)
	end

	if type(addrs) ~= "table" or #addrs == 0 then
		log.error("balance addrs not found,name=", service_name)
		return ngx.exit(ngx.HTTP_NOT_FOUND)
	end

	local ok, err = ngx_balancer.set_current_peer(addrs[1].addr, addrs[1].port)
    if not ok then
        log.error("failed to set the current peer: ", err)
        return ngx.exit(ngx.HTTP_NOT_FOUND)
    end
end

function _M:log() 
end

return _M

