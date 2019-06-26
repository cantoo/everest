local cjson = require("cjson.safe")
local etcdcli = require("resty.registry.etcdcli")
local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_lock = require("resty.lock")
local log = require("resty.log")

local new_tab = table.new
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local exiting = ngx.worker.exiting
local json_encode = cjson.encode
local json_decode = cjson.decode
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local to_hex = resty_string.to_hex
local random_bytes = resty_random.bytes
local ngx_timer_at = ngx.timer.at
local ngx_worker_id = ngx.worker.id

local registry = ngx.shared.registry
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
    local version = conf.version

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
        version = version,
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
            local ok = client:put(encode_base64(key), encode_base64(json_encode({
                add = self.addr, 
                metadata={version = self.version}})), lease)
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
    local key = encode_base64(table_concat(registry_path, service_name, "/"))
    local range_end = encode_base64(table_concat(key, "a"))
    return key, range_end
end

local function _watch(etcd, service_name)
    local addrs, err = registry:get(service_name)
    if not addrs then
        log.error(err)
        return err
    end

    local key, range_end = _get_key_range_end(service_name)

    while not exiting() do
        local reader, httpc
        reader, httpc, err = etcd.client:watch(key, range_end)
        if not reader then
            log.error(err)
            httpc:close()
            ngx.sleep(etcd.client.watch_timeout)
        end

        while not exiting() do
            local chunk
            chunk, err = reader()
            if err then 
                log.error(err)
                if not string.find(err, "timeout") then
                    break
                end
            end

            log.debug("service_name=", service_name, ",chunk=", chunk)
            if chunk then
                local res = json_decode(chunk)
                if not res then
                    log.error("failed to decode chunk=", chunk)
                else
                    if type(res.events) == "table" then
                        for _, event in ipairs(res.events) do
                            if type(event.kv) == "table" and (event.type == "PUT" or event.kv.version == "1") then
                                local caddr = json_decode(decode_base64(event.kv.value))
                                if not caddr or not caddr.addr then
                                    log.error("failed to decode or invalid event value=", event.kv.value)
                                else
                                    local i = 1
                                    while i <= #addrs do
                                        if caddr.addr == addrs[i].addr then
                                            break
                                        end
                                        
                                        i = i + 1
                                    end

                                    addrs[i] = caddr
                                end
                            elseif event.type == "DELETE" and type(event.kv) == "table" then
                                local key = decode_base64(event.kv.key)
                                local i = 1
                                while i <= #addrs do
                                    if key == addrs[i].addr then
                                        break
                                    end
                                    
                                    i = i + 1
                                end

                                table_remove(addrs, i)
                            end
                        end

                        registry:set(service_name, json_encode(addrs))
                    end
                end

                -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"34","raft_term":"3"},"created":true}}

                -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"35","raft_term":"3"},"events":[{"kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","create_revision":"35","mod_revision":"35","version":"1","value":"eyJBZGRyIjoiNC4zLjIuMTo4ODg4In0=","lease":"7587839221445806083"}}]}}

                -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"36","raft_term":"3"},"events":[{"type":"DELETE","kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","mod_revision":"36"}}]}}es = json_decode(chunk)
            end
        end

        httpc:close()
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
    local kvs = self.client:range(key, range_end)
    if not kvs then
        lock:unlock()
        return false, nil
    end

    addrs = new_tab(100, 0)
    if type(kvs) == "table" then
        for _, kv in ipairs(kvs) do 
            if type(kv) == "table" and type(kv.value) == "string" then    
                local addr = json_decode(decode_base64(kv.value))
                if type(addr) == "table" and type(addr.addr) == "string" then
                    table_insert(addrs, addr)
                end
            end
        end
    end

    if #addrs == 0 then 
        lock:unlock()
        return false, nil
    end

    local ok
    ok, err = registry:set(service_name, json_encode(addrs))
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





