local restful = require("restful")

local table_concat = table.concat
local ngx_exit = ngx.exit
local ngx_var = ngx.var

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

restful:say(mod:run())
