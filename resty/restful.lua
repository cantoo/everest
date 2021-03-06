--[[
+---------------------------------------------------------------------------------+
|verb        |status                          |description                        |
|------------+--------------------------------+-----------------------------------|
|GET         |200 OK                          |查询ok, 正常返回数据               |
|------------+--------------------------------+-----------------------------------|
|ALL         |202 Accepted                    |请求已收到, 对请求的处理会异步执行 |
|------------+--------------------------------+-----------------------------------|
|POST/PUT    |201 CREATED                     |创建/修改成功                      |
|------------+--------------------------------+-----------------------------------|
|DELETE      |204 NO CONTENT                  |删除数据成功                       |
|------------+--------------------------------+-----------------------------------|
|GET         |304 Not Modified                |可使用客户端缓存                   |
|------------+--------------------------------+-----------------------------------|
|POST/PUT    |400 Bad Request                 |数据解析失败(如body为非json)       |
|------------+--------------------------------+-----------------------------------|
|ALL         |401 Unauthorized                |登录态过期                         |
|------------+--------------------------------+-----------------------------------|
|ALL         |403 Forbidden                   |资源未授权(如删除不属于自己的UGC)  |
|------------+--------------------------------+-----------------------------------|
|ALL         |404 NOT FOUND                   |资源不存在(从未存在过)             |
|------------+--------------------------------+-----------------------------------|
|ALL         |405 Method Not Allowed          |不支持的接口                       |
|------------+--------------------------------+-----------------------------------|
|ALL         |410 GONE                        |资源已经被删除(存在过, 但已删除)   |
|------------+--------------------------------+-----------------------------------|
|ALL         |422 Unprocessable Entity        |参数非法(参数取值或类型不支持)     |
|------------+--------------------------------+-----------------------------------|
|ALL         |423 Locked                      |当前资源被锁定                     |
|------------+--------------------------------+-----------------------------------|
|ALL         |429 Too Many Requests           |超过频率限制                       |
|------------+--------------------------------+-----------------------------------|
|ALL         |500 INTERNAL SERVER ERROR       |服务器内部错误                     |
+---------------------------------------------------------------------------------+
]]--

local cjson = require("cjson.safe")

local parse_http_time = ngx.parse_http_time
local http_time = ngx.http_time

local _M = {}


function _M.wrap(body, status)
    return { body = body, status = status }
end

function _M.ok(body, last_modified)
    local res = _M.wrap(body)
    if type(last_modified) == "number" then
        ngx.header["Last-Modified"] = http_time(last_modified)
    end

    return res
end

function _M.accepted(body)
    return _M.wrap(body, ngx.HTTP_ACCEPTED)
end

function _M.created(body)
    return _M.wrap(body, ngx.HTTP_CREATED)
end

function _M.no_content()
    return _M.wrap(nil, ngx.HTTP_NO_CONTENT )
end

function _M.if_modified_since()
    if not ngx.http_if_modified_since then
        return nil
    end

    return parse_http_time(ngx.http_if_modified_since)
end

function _M.not_modified()
    return _M.wrap(nil, ngx.HTTP_NOT_MODIFIED)
end

function _M.temporary_redirect(uri)
    local res = _M.wrap(nil, ngx.HTTP_TEMPORARY_REDIRECT)
    if type(uri) == "string" and #uri > 0 then
        ngx.header["Location"] = uri
    end

    return res
end

function _M.bad_request(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.BAD_REQUEST)
end

function _M.unauthorized(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_UNAUTHORIZED)
end

function _M.forbidden(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_FORBIDDEN)
end

function _M.not_found(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_NOT_FOUND)
end

function _M.method_not_allowed(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_METHOD_NOT_ALLOWED)
end

function _M.gone(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_GONE)
end

function _M.unprocessable_entity(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, 422)
end

function _M.locked(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, 423)
end

function _M.too_many_requests(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_TOO_MANY_REQUESTS)
end

function _M.internal_server_error(errmsg, errcode)
    return _M.wrap((errmsg or errcode) and {errmsg = errmsg, errcode = errcode}, ngx.HTTP_INTERNAL_SERVER_ERROR)
end

function _M.get_body_data()
    local body = ngx.req.get_body_data()
    if not body then
        return nil
    end

    return cjson.decode(body)
end

function _M.hypermedia(res, rel, uri, method)
    if type(res) ~= "table" then
        return
    end

    local default_method = {
        ["detail"] = "GET",
        ["previous"] = "GET",
        ["next"] = "GET",
        ["delete"] = "DELETE",
    }

    res.links = res.links or {}
    table.insert(res.links, {rel = rel, uri = uri, method = method or default_method[rel] or "GET"})
    return
end

function _M.success(res)
    if type(res) == "table" and type(res.status) == "number" and res.status >= 200 and res.status < 400 then
        return true
    end

    return false
end

function _M.say(res)
    local default_status = {
        ["GET"]     = 200,
        ["PUT"]     = 201,
        ["POST"]    = 201,
        ["DELETE"]  = 204,
    }

    res = res or {}
    ngx.status = res.status or default_status[ngx.var.echo_request_method]
    if type(res.body) == "table" then
        cjson.encode_empty_table_as_object(false)
        local body = cjson.encode(res.body)
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.header["Content-Length"] = #body + 1
        ngx.say(body)
    elseif res.body then
        local body = tostring(res.body)
        ngx.header["Content-Type"] = "text/plain; charset=utf-8"
        ngx.header["Content-Length"] = #body
        ngx.print(body)
    end

    ngx.eof()
end

return _M
