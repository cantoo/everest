local _M = {}

local mt = { __index = _M }

local ngx_spawn = ngx.thread.spawn
local ngx_wait = ngx.thread.wait

function _M:new()
    return setmetatable({threads = {}}, mt)
end

function _M:init()
    self.threads = {}
end

function _M:spawn(func, ...)
    if type(func) ~= "function" then
        error("only can spawn function")
    end

    table.insert(self.threads, ngx_spawn(func, ...))
end

function _M:wait()
    local threads = self.threads
    if not threads then
        error("not init yet")
    end

    local results = {}
    for i, thread in ipairs(threads) do
        results[i] = { ngx_wait(thread) }
    end

    return results
end

return _M













