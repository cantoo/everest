local cjson = require("cjson.safe")
local etcdcli = require("resty.registry.etcdcli")
local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_lock = require("resty.lock")
local log = require("resty.log")
local shell = require "resty.shell"

local run_shell = shell.run
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
    local hosts = conf.hosts or { { host = "127.0.0.1", port = 2379 } }
    local prefix = conf.prefix or "v3beta"
    local timeout = conf.timeout or 5
    local ttl = conf.ttl or 10
    local addr = conf.addr
    local ifa = conf.ifa or "eth0"
    local port = conf.port
    local name = conf.name 
    local version = conf.version

    local clients = new_tab(#hosts, 0)
    for _, host in ipairs(hosts) do
        table_insert(clients, etcdcli.new({
            host = host.host,
            port = host.port,
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
        ifa = ifa,
        port = port,
        ttl = ttl,
        timeout = timeout,
    }, mt)
end

local function register(_, self)
    local rand = tonumber(to_hex(random_bytes(4, true)), 16) % #self.clients + 1

    local addr = self.addr
    if not addr then
        _, addr = run_shell("/usr/sbin/ifconfig " .. self.ifa .. " | grep 'inet ' | awk '{print $2}'")
        addr = string.gsub(addr, "\n", "")
        log.debug("ifa=", self.ifa, ",addr=", addr)
    end

    if not addr then
        log.error("no addr")
        return 
    end

    while not exiting() do
        local client = self.clients[rand]
        self.client = client

        local lease = client:grant(self.timeout + self.ttl)

        if not lease then
            ngx.sleep(self.ttl)
        else
            local key = table_concat({registry_path, self.name, "/", addr, ":", self.port})
            local ok = client:put(encode_base64(key), encode_base64(json_encode({
                addr = addr, 
                port = self.port,
                metadata={version = self.version}})), lease)
            if not ok then
                client:revoke(lease)
                ngx.sleep(self.ttl)
            else
                while not exiting() do
                    ngx.sleep(self.ttl)
                    ok = client:keepalive(lease) 
                    if not ok then
                        break
                    end
                end

                client:revoke(lease)
            end
        end

        rand = (rand + 1) % #self.clients + 1
    end
end 

function _M:init_worker() 
    if ngx_worker_id() == 0 and 
        type(self.name) == "string" and self.name ~= "" and 
        type(self.port) == "number" and self.port ~= 0 then
        ngx_timer_at(0, register, self)
    end
end

local function _get_key_range_end(service_name)
    local key = encode_base64(table_concat({registry_path, service_name, "/"}))
    local range_end = encode_base64(table_concat({key, "a"}))
    return key, range_end
end

local function _watch(etcd, service_name)
    local addrs, err = registry:get(service_name)
    if not addrs then
        return err
    end

    local key, range_end = _get_key_range_end(service_name)

    while not exiting() do
        local reader, httpc = etcd.client:watch(key, range_end)
        if not reader then
            ngx.sleep(etcd.client.watch_timeout)
        else
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
                                if type(event.kv) == "table" then
                                    local caddr = json_decode(decode_base64(event.kv.value))
                                    if not caddr or not caddr.addr or caddr.port then
                                        log.error("failed to decode or invalid event value=", event.kv.value)
                                    else
                                        if event.type == "PUT" or event.kv.version == "1" then
                                            local i = 1
                                            while i <= #addrs do
                                                if caddr.addr == addrs[i].addr and caddr.port == addrs[i].port then
                                                    break
                                                end
                                                
                                                i = i + 1
                                            end

                                            addrs[i] = caddr
                                        elseif event.type == "DELETE" then
                                            local i = 1
                                            while i <= #addrs do
                                                if caddr == addrs[i].addr and caddr.port == addrs[i].port then
                                                    break
                                                end
                                                
                                                i = i + 1
                                            end

                                            table_remove(addrs, i)
                                        end
                                    end
                                end
                            end

                            if #addrs == 0 then
                                registry.delete(service_name)
                                httpc:close()
                                return
                            else
                                registry:set(service_name, json_encode(addrs))
                            end
                        end
                    end

                    -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"34","raft_term":"3"},"created":true}}

                    -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"35","raft_term":"3"},"events":[{"kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","create_revision":"35","mod_revision":"35","version":"1","value":"eyJBZGRyIjoiNC4zLjIuMTo4ODg4In0=","lease":"7587839221445806083"}}]}}

                    -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"36","raft_term":"3"},"events":[{"type":"DELETE","kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","mod_revision":"36"}}]}}es = json_decode(chunk)
                end
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
        return false, err
    end

    local lock
    lock, err = resty_lock:new(registry_lock)
    if not lock then
        log.error(err)
        return false, err
    end

    local elapsed
    elapsed, err = lock:lock(service_name)
    if not elapsed then
        log.error(err)
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
                if type(addr) == "table" and type(addr.addr) == "string" and type(addr.port) == "number" then
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
        log.error(err)
    end

    lock:unlock()
    return true, nil
end

return _M




