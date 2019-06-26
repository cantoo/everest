local ngx_log = ngx.log
local ngx_var = ngx.var
local debug_info = debug.getinfo
local format = string.format
local get_phase = ngx.get_phase
local cur_level = require("ngx.errlog").get_sys_filter_level()

local _M = {version = 0.1}

for name, log_level in pairs({stderr = ngx.STDERR,
                              emerg  = ngx.EMERG,
                              alert  = ngx.ALERT,
                              crit   = ngx.CRIT,
                              error  = ngx.ERR,
                              warn   = ngx.WARN,
                              notice = ngx.NOTICE,
                              info   = ngx.INFO, }) do
    _M[name] = function(...)
        if cur_level and log_level > cur_level then
            return
        end

        local phase = get_phase()
        local request_id = phase
        if phase == "rewrite" or phase == "access" or phase == "content" then
            request_id = ngx_var.http_x_request_id
        end

        local info = debug_info(2, "nSl")
        local extra = format(" [%s] %s %s:%d: ", request_id, info.name, info.short_src, info.currentline)
        return ngx_log(log_level, extra, ...)
    end
end

return _M
