local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_md5 = require("resty.md5")

local to_hex = resty_string.to_hex
local random_bytes = resty_random.bytes
local string_len = string.len
local string_sub = string.sub
local string_gsub = string.gsub
local table_concat = table.concat
local md5_new = resty_md5.new

local _M = {}

function _M.hash(str)
    if type(str) == "number" then
        return str
    end

    local ret = tonumber(str)
    if ret then
        return ret
    end

    local hex = to_hex(str)
    local len = string_len(hex)
    if len > 8 then
        hex = string_sub(hex, -8)
    end

    ret = tonumber(hex, 16)
    return ret
end

function _M.from_hex(hex)
    return string_gsub(hex, "%x%x", function(c) return string.char(tonumber(c, 16)) end)
end

function _M.get_day_begin(day)
    day = day or ngx.time()
    return (day - (day - 57600) % 86400)
end

function _M.md5sum(...)
    local args = { ... }

    local md5 = md5_new()
    if not md5 then
        return nil, "failed to create md5 object"
    end

    local ok = md5:update(table_concat(args))
    if not ok then
        return nil, "failed to add data"
    end

    local digest = md5:final()
    return to_hex(digest)
end

function _M.random(bytes)
    return tonumber(to_hex(random_bytes(bytes, true)), 16)
end

return _M




