local http = require("resty.http")
local cjson = require("cjson.safe")
local threads = require("threads")

local cjson_decode = cjson.decode
local cjson_encode = cjson.encode
local table_concat = table.concat
local ngx_capture = ngx.location.capture
local ngx_capture_multi = ngx.location.capture_multi
local ngx_get_headers = ngx.req.get_headers
local ngx_phase = ngx.get_phase

local method_num2str = {
    [ngx.HTTP_GET] = "GET",
    [ngx.HTTP_PUT] = "PUT",
    [ngx.HTTP_POST] = "POST",
    [ngx.HTTP_DELETE] = "DELETE"
}

local method_str2num = {
    ["GET"] = ngx.HTTP_GET,
    ["PUT"] = ngx.HTTP_PUT,
    ["POST"] = ngx.HTTP_POST,
    ["DELETE"] = ngx.HTTP_DELETE
}

local _M = {}

local mt = { __index = _M }

local function _build_resp(res, err, options)
    res = res or {}
    options = options or {}

    if res.body and not options.donot_decode then
        if res.body == "" then
            res.body = nil
        else
            local json_body = cjson_decode(res.body)
            if not json_body then
                err = "fail to decode resp body"
            else
                res.body = json_body
            end
        end
    end

    local resp = { body = res.body, header = res.header, status = res.status }
    if err then
        resp.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        resp.err = err
    elseif type(res.status) == "number" and res.status >= 400 then
        resp.err = "status " .. res.status
    elseif res.truncated then
        resp.err = "body truncated"
    end

    return resp
end

function _M:new(prefix, server_port)
    return setmetatable({prefix = prefix, server_port = server_port or ngx.var.server_port}, mt)
end

-- params = [
--     { location, uri, options },
--     { location, uri, options },
-- ]
-- ngx.location.capture_multi是在同一个worker里面执行
-- 多个请求的cpu部分是分时间占用cpu的, cpu部分无法并发
-- 使用ngx.thread.spawn + http请求可能会分散到多个Worker同时处理, cpu部分也能并发
-- 默认情况使用ngx.location.capture_multi, 除非指定使用ngx.thread.spawn + http
function _M:capture_multi(params, use_http)
    for _, param in ipairs(params) do
        if type(param) ~= "table" then
            error("wrong param, table expected")
        end

        local location = param[1]
        if type(location) ~= "table" then
            error("capture_multi need location")
        end

        local uri = param[2]
        if type(uri) ~= "string" then
            error("capture_multi need uri")
        end
    end

    local resps = {}
    if use_http or ngx_phase() == "timer" then
        local thds = threads:new()
        for _, param in ipairs(params) do
            local options = param[3] or {}
            options.use_http = true
            if ngx_phase() ~= "timer" and not options.headers then
                options.headers = ngx_get_headers()
            end

            thds:spawn(param[1].capture, param[1], param[2], options)
        end

        local results = thds:wait()
        for i, result in ipairs(results) do
            local err
            local ok, res = result[1], result[2]
            if not ok then
                err = "thread exception " .. res
                res = nil
            end

            resps[i] = _build_resp(res, err, params[i][3])
        end
    else
        local captures = {}
        for _, param in ipairs(params) do
            table.insert(captures, {param[1].prefix .. param[2], param[3]})
        end

        local results = { ngx_capture_multi(captures) }
        for i, res in ipairs(results) do
            resps[i] = _build_resp(res, nil, params[i][3])
        end
    end

    return resps
end

function _M:capture(uri, options)
    if not self.prefix then
        error("not init yet")
    end

    local res, err
    options = options or {}
    if type(options.body) == "table" then
        options.body = cjson_encode(options.body)
    end

    if options.use_http or ngx_phase() == "timer" then
        local params = {}
        -- method
        params.method = options.method
        if type(options.method) == "number" then
            params.method = method_num2str[options.method]
        end

        -- query
        params.query = options.args
        if type(options.args) == "table" then
            params.query = cjson_encode(options.args)
        end

        -- headers
        params.headers = options.headers
        if ngx_phase() ~= "timer" and not options.headers then
            params.headers = ngx_get_headers()
        end

        -- body
        params.body = options.body

        -- ssl_verify
        params.ssl_verify = options.ssl_verify

        -- uri
        local full_uri = table_concat({"http://127.0.0.1:", self.server_port, self.prefix, uri})

        -- timeout
        local httpc = http:new()
        httpc:set_timeout(options.timeout or 5)

        res, err = httpc:request_uri(full_uri, params)
        if res and res.headers then
            res.header = res.headers
        end
    else
        res = ngx_capture(self.prefix .. uri, options)
    end

    return _build_resp(res, err, options)
end

function _M:get(uri, options)
    options = options or {}
    options.method = ngx.HTTP_GET
    return self:capture(uri, options)
end

function _M:put(uri, options)
    options = options or {}
    options.method = ngx.HTTP_PUT
    return self:capture(uri, options)
end

function _M:post(uri, options)
    options = options or {}
    options.method = ngx.HTTP_POST
    return self:capture(uri, options)
end

function _M:delete(uri, options)
    options = options or {}
    options.method = ngx.HTTP_DELETE
    return self:capture(uri, options)
end

function _M:proxy()
    return self:capture(ngx.var.echo_request_uri, {
        method = method_str2num[ngx.var.echo_request_method],
        always_forward_body = true
    })
end

return _M













