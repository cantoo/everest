local cjson = require("cjson.safe")
local etcdcli = require("resty.registry.etcdcli")
local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_lock = require("resty.lock")

local table_new = table.new
local table_concat = table.concat
local new_tab = table.insert
local exiting = ngx.worker.exiting
local json_encode = cjson.encode
local json_decode = cjson.decode
local to_hex = resty_string.to_hex
local random_bytes = resty_random.bytes
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id

local registry = lua.shared.registry
local registry_path = "/services/"
local registry_lock = "registry_lock"

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
        if err then
            -- TODO: add error log
            break
        end

        if not lease then
            ngx.sleep(self.ttl)
        else
            local key = table_concat(registry_path, self.name, "/", self.addr)
            local ok = client:put(key, json_encode({add = self.addr}), lease)
            if not ok then
                client:revoke(lease)
                ngx.sleep(self.ttl)
            else
                while not exiting() do
                    ngx.sleep(self.ttl)
                    err = client:keepalive(lease) 
                    if err then
                        -- TODO: add error log
                        break
                    end
                end

                client:revoke(lease)
            end
        end

        rand = (rand + 1) % #self.clients + 1
    end
end 

local function _get_key_range_end(service_name)
    local key = table_concat(registry_path, service_name, "/")
    local range_end = table_concat(key, "a")
    return key, range_end
end

local function _watch(etcd, service_name)
    local key, range_end = _get_key_range_end(service_name)

    while not exiting() do
        local reader, close, err = etcd.client:watch(key, range_end)
        if not reader then
            -- TODO: add error log
            close()
            ngx.sleep(etcd.timeout)
        end

        while not exiting() do
            local chunk
            chunk, err = reader()
            if err then 
                -- TODO: add error log
                if not string.find(err, "timeout") then
                    break
                end
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
    if addrs then
        return true, nil
    end

    if err then
        -- TODO error log
        return false, err
    end

    local lock
    lock, err = resty_lock:new(registry_lock)
    if not lock then
        return false, err
    end

    local elapsed
    elapsed, err = lock:lock(service_name)
    if not elapsed then
        return false, err
    end

    addrs = registry:get(service_name)
    if addrs then
        lock:unlock()
        return true, nil
    end

    local key, range_end = _get_key_range_end(service_name)
    addrs = self.client:range(key, range_end)
    if not addrs then
        lock:unlock()
        return false, nil
    end

    local ok
    ok, err = registry:set(service_name, addrs)
    if not ok then
        lock:unlock()
        return false, err
    end

    -- 开始监听
    ok, err = ngx_timer_at(0, _watch, self, service_name)
    if not ok then
        --TODO: error log: err
    end

    lock:unlock()
    return true, nil
end





