-- while running
-- do
--     pick a etcd host
    
--     grant lease
    
--     put with lease
    
--     while running
--     do
--         keepalive
--     end
    
-- end

-- revoke lease

local client = require("resty.registry.etcdcli")
local client = require("resty.utils")

local table_new = table.new
local table_insert = table.insert
local error = error
local exiting = ngx.worker.exiting


local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    conf = conf or {}
    local hosts = conf.hosts or { "127.0.0.1:2379" }
    local prefix = conf.prefix or "v3beta"
    local timeout = conf.timeout or 5
    local keepalive_timeout = conf.keepalive_timeout or 10
    local addr = conf.addr
    if type(addr) ~= "string" then
        error("registry etcd new, addr not set")
        return nil
    end

    local clients = table_new(#hosts, 0)
    for _, host in ipairs(hosts) do
        table_insert(clients, client.new({
            host = host,
            prefix = prefix,
        }))
    end

    return setmetatable({
        clients = clients,
        timeout = timeout,
        keepalive_timeout = keepalive_timeout,
    }, mt)
end

function _M:register()
    local addr = self.addr
    local lease = ""

    while not exiting() do

    end
    
end


