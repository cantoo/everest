local cjson = require("cjson.safe")

local cjson_encode = cjson.encode
local table_concat = table.concat
local ngx_exit = ngx.exit
local ngx_say = ngx.say
local ngx_print = ngx.print
local ngx_header = ngx.header
local ngx_eof = ngx.eof
local ngx_var = ngx.var

local default_status = {
    ["get"]     = 200,
    ["put"]     = 201,
    ["post"]    = 201,
    ["delete"]  = 204,
}

local res1 = ngx_var[1]
local res2 = ngx_var[3]
local res3 = ngx_var[5]
local server_port = ngx_var.server_port
local echo_request_method = string.lower(ngx_var.echo_request_method)
local res1_sub = ngx.re.match(res1, ".*_(.*)$")
res1_sub = res1_sub and res1_sub[1] or res1

local method_resources_file = table_concat({echo_request_method, res1, res2, res3}, "_")
--local success, mod = pcall(require, table_concat({server_port, res1_sub, method_resources_file}, "."))
local success, mod = true, require(table_concat({server_port, res1_sub, method_resources_file}, "."))
if not success or not mod or type(mod.run) ~= "function" then
    ngx_exit(ngx.HTTP_NOT_FOUND)
end

local res = mod:run()
if type(res) ~= "table" then
    ngx_exit(ngx.INTERNAL_SERVER_ERROR)
end

ngx.status = res.status or default_status[echo_request_method]
if type(res.header) == "table" then
    for key, value in pairs(res.header) do
        ngx_header[key] = value
    end
end

if type(res.body) == "table" then
    cjson.encode_empty_table_as_object(false)
    local body = cjson_encode(res.body)
    ngx_header["Content-Type"] = "application/json; charset=utf-8"
    ngx_header["Content-Length"] = #body + 1
    ngx_say(body)
elseif res.body then
    local body = tostring(res.body)
    ngx_header["Content-Length"] = #body
    ngx_print(body)
end

ngx_eof()
