local cjson = require("cjson.safe")
local etcdcli = require("resty.registry.etcdcli")
local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_lock = require("resty.lock")

local table_new = table.new
local new_tab = table.insert
local exiting = ngx.worker.exiting
local json_encode = cjson.encode
local json_decode = cjson.decode
local to_hex = resty_string.to_hex
local random_bytes = resty_random.bytes
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id
local registry = lua.shared.registry

local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    local hosts = conf.hosts or { "127.0.0.1:2379" }
    local prefix = conf.prefix or "v3beta"
    local timeout = conf.timeout or 5
    local ttl = conf.ttl or 10
    local addr = conf.addr
    local name = conf.name 

    local clients = new_tab(#hosts, 0)
    for _, host in ipairs(hosts) do
        table_insert(clients, etcdcli.new({
            host = host,
            prefix = prefix,
            timeout = timeout,
        }))
    end

    return setmetatable({
        clients = clients,
        client = clients[1],
        name = name,
        addr = addr,
        ttl = ttl,
        timeout = timeout,
    }, mt)
end

function _M:init_worker() 
    if ngx_worker_id() == 0 and 
        type(self.name) == "string" and self.name ~= "" and 
        type(self.addr) == "string" and self.addr ~= "" then
        ngx_timer_at(0, self.register, self)
    end
end

function _M:register()
    local rand = tonumber(to_hex(random_bytes(4, true)), 16) % #self.clients + 1

    while not exiting() do
        local client = self.clients[rand]
        self.client = client

        local lease, err = client:grant(self.timeout + self.ttl)
        if err ~= nil then
            -- TODO: add error log
            break
        end

        local key = "/services/" .. self.name .. "/" .. self.addr
        err = client:put(key, json_encode({add = self.addr}), lease)
        if err ~= nil then
            break
        end

        while not exiting() do
            ngx.sleep(self.ttl)
            err = client:keepalive(lease) 
            if err ~= nil then
                -- TODO: add error log
                break
            end
        end

        client:revoke(lease)
        rand = (rand + 1) % #self.clients + 1
    end
end 

local function _get_key_range_end(service_name)
    -- TODO
    return service_name, service_name
end

local function _watch(etcd, service_name)
    local key, range_end = _get_key_range_end(service_name)

    while not exiting() do
        local reader, close, err = etcd.client:watch(key, range_end)
        if err ~= nil then
            close()
            ngx.sleep(etcd.timeout)
        end

        while not exiting() do
            local chunk
            chunk, err = reader()
            if err ~= nil then 
                -- TODO: add error log
                break
            end

            -- TODO: add debug log

            if chunk then
                --local res = json_decode(chunk)
                -- deal with res
            end
        end

        close()
    end
end

function _M:prepare(service_name)
    local addrs, err = registry:get(service_name)
    if err ~= nil then
        -- TODO error log
        return false, err
    end

    if addrs ~= nil then
        return true, nil
    end

    local lock
    lock, err = resty_lock:new("registry_lock")
    if not lock then
        return err
    end

    local elapsed
    elapsed, err = lock:lock(service_name)
    if not elapsed then
        return err
    end

    local key, range_end = _get_key_range_end(service_name)
    local res
    res, err = self.client:range(key, range_end)
    if err ~= nil then
        local ok2, err2 = lock:unlock()
        if not ok2 then
            --TODO: error log: err2
        end

        return err
    end

    -- TODO range result to addrs
    addrs = res

    local ok
    ok, err = registry:set(service_name, addrs)
    if not ok then
        local ok2, err2 = lock:unlock()
        if not ok2 then
            --TODO: error log: err2
        end

        return err
    end

    -- 开始监听
    ngx_timer_at(0, _watch, self, service_name)

    local ok2, err2 = lock:unlock()
    if not ok2 then
        --TODO: error log: err2
    end

    return true, nil
end





