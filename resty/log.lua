local ngx_log = ngx.log
local ngx_var = ngx.var
local format = string.format
local get_phase = ngx.get_phase
local cur_level = require("ngx.errlog").get_sys_filter_level()

local _M = {version = 0.1}

local log_levels = {
    { name = "stderr", level = ngx.STDERR },
    { name = "emerg",  level = ngx.EMERG },
    { name = "alert",  level = ngx.ALERT },
    { name = "crit",   level = ngx.CRIT },
    { name = "error",  level = ngx.ERR },
    { name = "warn",   level = ngx.WARN },
    { name = "notice", level = ngx.NOTICE },
    { name = "info",   level = ngx.INFO },
    { name = "debug",  level = ngx.DEBUG },
}

for _, log_level in ipairs(log_levels) do
    _M[log_level.name] = function(...)
        if cur_level and log_level.level > cur_level then
            return
        end

        local phase = get_phase()
        local request_id = phase
        if phase == "rewrite" or phase == "access" or phase == "content" then
            request_id = ngx_var.http_x_request_id
        end

        local extra = format("[%s] ", request_id)
        return ngx_log(log_level.level, extra, ...)
    end
end

return _M
