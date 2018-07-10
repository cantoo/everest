local cjson = require("cjson.safe")
local http = require("resty.http")

local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local ngx_capture = ngx.location.capture
local ngx_phase = ngx.get_phase

local _M = {}
local mt = { __index = _M }

function _M:new(prefix)
    return setmetatable({prefix = prefix}, mt)
end

function _M:subrequest(uri, options)
    if type(options) == "table" and type(options.body) == "table" then
        options.body = cjson_encode(body)
    end

    local res = ngx_capture(uri, options)
    if type(res) == "table" and type(res.body) == "string" then
        res.body = cjson_decode(res.body)
    end

    return res
end

function _M:httprequest(uri, options)
    if type(options) == "table" then
        if type(options.method) == "number" then
            local method_num2str = {
                [ngx.HTTP_GET] = "GET",
                [ngx.HTTP_PUT] = "PUT",
                [ngx.HTTP_POST] = "POST",
                [ngx.HTTP_DELETE] = "DELETE"
            }

            options.method = method_num2str(options.method)
        end

        if not options.query and options.args then
            options.query = options.args
        end

        if type(options.body) == "table" then
            options.body = cjson_encode(body)
        end
    end

    local httpc = http:new()
    httpc:set_timeout(options.timeout or 5000)
    local res, err = httpc:request_uri("http://127.0.0.1" .. uri, params)

    res = res or {}
    if type(res.headers) == "table" then
        res.header = res.headers
    end

    if type(res.body) == "string" then
        res.body = cjson_decode(res.body)
    end

    if err then
        res.status = ngx.HTTP_INTERNAL_SERVER_ERROR
        res.err = err
    end

    return res
end

function _M:capture(uri, options)
    if ngx_phase() == "timer" then
        return _M:httprequest(uri, options)
    end

    return _M:subrequest(uri, options)
end

function _M:get(uri, options)
    options = options or {}
    options.method = ngx.HTTP_GET
    return _M:capture(self.prefix .. uri, options)
end

function _M:put(uri, options)
    options = options or {}
    options.method = ngx.HTTP_PUT
    return _M:capture(self.prefix .. uri, options)
end

function _M:post(uri, options)
    options = options or {}
    options.method = ngx.HTTP_POST
    return _M:capture(self.prefix .. uri, options)
end

function _M:delete(uri, options)
    options = options or {}
    options.method = ngx.HTTP_DELETE
    return _M:capture(self.prefix .. uri, options)
end

function _M:proxy()
    return _M:subrequest(self.prefix .. ngx.var.echo_request_uri, {
        method = ngx.var.echo_request_method,
        args = ngx.var.args,
        always_forward_body = true,
    })
end



return _M