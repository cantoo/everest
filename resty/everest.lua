local restful = require("resty.restful")

local table_concat = table.concat
local ngx_var = ngx.var

local res1 = ngx_var[1]
local echo_request_method = string.lower(ngx_var.echo_request_method)
local method_resources_file = table_concat({echo_request_method, res1, ngx_var[3], ngx_var[5]}, "_")
local res1_sub = ngx.re.match(res1, ".*_(.*)$")
res1_sub = res1_sub and res1_sub[1] or res1

local handler = require(table_concat({res1_sub, method_resources_file}, "."))
restful.say(handler.handle())
