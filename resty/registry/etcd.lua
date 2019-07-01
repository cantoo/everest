local cjson = require("cjson.safe")
local etcdcli = require("resty.registry.etcdcli")
local resty_string = require("resty.string")
local resty_random = require("resty.random")
local resty_lock = require("resty.lock")
local log = require("resty.log")
local shell = require("resty.shell")

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
    conf = conf or {}
    local hosts = conf.hosts or { { host = "127.0.0.1", port = 2379 } }
    local prefix = conf.prefix
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

local function _get_registry_key(name, addr, port)
    return table_concat({registry_path, name, "/", addr, ":", port})
end

local function _get_key_range_end(service_name)
    local key = table_concat({registry_path, service_name, "/"})
    local range_end = encode_base64(table_concat({key, "a"}))
    key = encode_base64(key)
    return key, range_end
end

local function register(_, etcd)
    local rand = tonumber(to_hex(random_bytes(4, true)), 16) % #etcd.clients + 1

    local addr = etcd.addr
    if not addr then
        _, addr = run_shell("/usr/sbin/ifconfig " .. etcd.ifa .. " | grep 'inet ' | awk '{print $2}'")
        addr = string.gsub(addr, "\n", "")
        log.debug("ifa=", etcd.ifa, ",addr=", addr)
    end

    if not addr or addr == "" then
        log.error("no addr")
        return 
    end

    while not exiting() do
        local client = etcd.clients[rand]
        etcd.client = client

        local lease = client:grant(etcd.timeout + etcd.ttl)

        if not lease then
            ngx.sleep(etcd.ttl)
        else
            local key = _get_registry_key(etcd.name, addr, etcd.port)
            local ok = client:put(encode_base64(key), encode_base64(json_encode({
                addr = addr, 
                port = etcd.port,
                metadata={version = etcd.version}})), lease)
            if not ok then
                client:revoke(lease)
                ngx.sleep(etcd.ttl)
            else
                while not exiting() do
                    ngx.sleep(etcd.ttl)
                    ok = client:keepalive(lease) 
                    if not ok then
                        break
                    end
                end

                client:revoke(lease)
            end
        end

        rand = (rand + 1) % #etcd.clients + 1
    end
end 

function _M:init_worker() 
    if ngx_worker_id() == 0 and 
        type(self.name) == "string" and self.name ~= "" and 
        type(self.port) == "number" and self.port ~= 0 then
        ngx_timer_at(0, register, self)
    end
end

local function _watch(_, etcd, service_name)
    local value, err = registry:get(service_name)
    if not value then
        return err
    end

    local addrs = json_decode(value)
    if not addrs then
        registry:delete(service_name)
        log.debug("failed to json decode addrs service_name=" .. service_name, ",value=", value)
        return
    end

    local key, range_end = _get_key_range_end(service_name)

    while not exiting() do
        local reader, httpc = etcd.client:watch(key, range_end)
        if not reader then
            ngx.sleep(etcd.timeout)
        else
            while not exiting() do
                local chunk, err = reader()
                if err then 
                    log.error(err)
                    break
                end

                log.debug("service_name=", service_name, ",chunk=", chunk, ",err=", err)
                if chunk then
                    local res = json_decode(chunk)
                    if not res then
                        log.error("failed to decode chunk=", chunk, ",service_name=", service_name)
                        break
                    end

                    if type(res.result) == "table" and type(res.result.events) == "table" then
                        for _, event in ipairs(res.result.events) do
                            if type(event.kv) == "table" and type(event.kv.key) == "string" then
                                local registry_key = decode_base64(event.kv.key)
                                local i = 1
                                while i <= #addrs do
                                    if registry_key == _get_registry_key(service_name, addrs[i].addr, addrs[i].port) then
                                        break
                                    end
                                    
                                    i = i + 1
                                end

                                if event.type == "DELETE" then
                                    -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"36","raft_term":"3"},"events":[{"type":"DELETE","kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","mod_revision":"36"}}]}}es = json_decode(chunk)
                                    if i <= #addrs then
                                        table_remove(addrs, i)
                                    end
                                else
                                    -- {"result":{"header":{"cluster_id":"14841639068965178418","member_id":"10276657743932975437","revision":"35","raft_term":"3"},"events":[{"kv":{"key":"c2VydmljZXMvNC4zLjIuMQ==","create_revision":"35","mod_revision":"35","version":"1","value":"eyJBZGRyIjoiNC4zLjIuMTo4ODg4In0=","lease":"7587839221445806083"}}]}}
                                    value = json_decode(decode_base64(event.kv.value))
                                    if not value or type(value.addr) ~= "string" or type(value.port) ~= "number" then
                                        log.error("failed to decode event value=", event.kv.value, ",service_name=", service_name)
                                    else
                                        if i <= #addrs then
                                            addrs[i] = value
                                        else
                                            table_insert(addrs, value)
                                        end
                                    end
                                end
                            end
                        end

                        value = json_encode(addrs)
                        registry:set(service_name, value)
                        log.debug("update ", service_name, " addrs=", value)  
                    end
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
        log.error(err)
        return false, err
    end

    local lock, err = resty_lock:new(registry_lock)
    if not lock then
        log.error(err)
        return false, err
    end

    local elapsed, err = lock:lock(service_name)
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
        log.debug("range no result " .. service_name)
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
        log.debug("no addrs of " .. service_name)
        lock:unlock()
        return false, nil
    end

    local value = json_encode(addrs)
    local ok, err = registry:set(service_name, value)
    if not ok then
        log.error(err)
        lock:unlock()
        return false, err
    end

    log.debug("service_name=", service_name, ",addrs=", value)

    -- 开始监听
    ok, err = ngx_timer_at(0, _watch, self, service_name)
    if not ok then
        log.error(err)
    end

    lock:unlock()
    ngx.ctx.service_name = service_name
    return true, nil
end

return _M




