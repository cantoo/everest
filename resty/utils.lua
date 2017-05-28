local resty_string = require("resty.string")

local _M = {}

function _M:hash(str)
    if type(str) == "number" then
        return str
    end

    local ret = tonumber(str)
    if ret then
        return ret
    end

    local hex = resty_string.to_hex(str)
    local len = string.len(hex)
    if len > 8 then
        hex = string.sub(hex, -8)
    end

    ret = tonumber(hex, 16)
    return ret
end

function _M:from_hex(hex)
    return string.gsub(hex, "%x%x", function(c) return string.char(tonumber(c, 16)) end)
end

return _M




