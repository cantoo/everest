local mysql = require("resty.mysql")

local ngx_re_sub = ngx.re.sub

local _M = {
    NOT_FOUND = 3,
    NO_AFFECTED = 4,
}

local mt = { __index = _M }


function _M:new(conf)
    if not conf or not conf.host or not conf.user
        or not conf.password then
        error("host, user and password required")
    end

    local timeout = conf.timeout or 2000
    local port = conf.port or 3306
    local max_packet_size = conf.max_packet_size or 4 * 1024 * 1024
    local pool_size = conf.pool_size or 20
    local max_idle_timeout = conf.max_idle_timeout or 60000

    return setmetatable({
        timeout = timeout,
        port = port,
        max_packet_size = max_packet_size,
        pool_size = pool_size,
        max_idle_timeout = max_idle_timeout,
        host = conf.host,
        user = conf.user,
        password = conf.password,
        database = conf.database}, mt)
end

function _M:connect()
    local db = mysql:new()
    if not db then
        return nil, "failed to instance mysql"
    end

    db:set_timeout(self.timeout)
    local ok, err, errcode, sqlstate = db:connect({
        host = self.host,
        user = self.user,
        password = self.password,
        database = self.database,
        port = self.port,
        max_packet_size = self.max_packet_size})

    if not ok then
        ngx.log(ngx.ERR, "failed to connect: ", err, ": ", errcode, " ", sqlstate)
        return nil, err, errcode, sqlstate
    end

    return db
end

function _M:query_db(db, sql, nrows)
    local res, err, errcode, sqlstate = db:query(sql, nrows)
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errcode, ": ", sqlstate, ",sql=", sql)
        return nil, err, errcode
    end

    return res
end

function _M:set_keepalive(db)
    return db:set_keepalive(self.max_idle_timeout, self.pool_size)
end

-- 查询单条记录, 不存在返回not found
-- 返回 data, err, errcode, sqlstate
function _M:get(sql)
    local db, err, errcode, sqlstate = self:connect()
    if not db then
        return nil, err, errcode, sqlstate
    end

    local res
    res, err, errcode, sqlstate = self:query_db(db, sql, 1)
    if not res then
        return nil, err, errcode, sqlstate
    end

    self:set_keepalive(db)
    if type(res) == "table" and #res > 0 then
        return res[1]
    end

    return nil, "not found", _M.NOT_FOUND
end

-- 查询多条记录
-- 返回 data, err, errcode, sqlstate
function _M:query(sql)
    local db, err, errcode, sqlstate = self:connect()
    if not db then
        return nil, err, errcode, sqlstate
    end

    local res
    res, err, errcode, sqlstate = self:query_db(db, sql)
    if not res then
        return nil, err, errcode, sqlstate
    end

    self:set_keepalive(db)
    return res
end

-- 带limit查询分页记录
-- 返回 data, total, err, errcode, sqlstate
function _M:query_page(sql)
    local sqls = {ngx_re_sub(sql, "select ", "select SQL_CALC_FOUND_ROWS ", "ajo"), "select found_rows() as total"}
    local res, err, errcode, sqlstate = self:query_multi_resultset(sqls)
    if not res then
        return nil, nil, err, errcode, sqlstate
    end

    local data
    data, err, errcode, sqlstate = unpack(res[1])
    if not data then
        return nil, nil, err, errcode, sqlstate
    end

    return data or {}, tonumber(res[2][1].total) or 0
end

-- 执行update/insert
-- 返回 res, err, errcode, sqlstate
function _M:execute(sql)
    local db, err, errcode, sqlstate = self:connect()
    if not db then
        return nil, err, errcode, sqlstate
    end

    local res
    res, err, errcode, sqlstate = self:query_db(db, sql)
    if not res then
        return nil, err, errcode, sqlstate
    end

    self:set_keepalive(db)
    if type(res.affected_rows) ~= "number" or res.affected_rows == 0 then
        ngx.log(ngx.ERR, "no affected,sql=", sql)
        return nil, "no affected", _M.NO_AFFECTED
    end

    return res
end

-- 执行多个sql
-- 返回 [res1, res2]
function _M:query_multi_resultset(sqls)
    local db, err, errcode, sqlstate = self:connect()
    if not db then
        return nil, err, errcode, sqlstate
    end

    local res
    res, err, errcode, sqlstate = self:query_db(db, table.concat(sqls, "; ") .. ";")
    if not res then
        return nil, err, errcode, sqlstate
    end

    local multi_resultset = { res }
    local i = 2
    while err == "again" do
        res, err, errcode, sqlstate = db:read_result()
        if not res then
            ngx.log(ngx.ERR, "bad result #", i, ": ", err, ": ", errcode, ": ", sqlstate, ",sql=", sqls[i])
            return nil, err, errcode, sqlstate
        end

        table.insert(multi_resultset, res)
        i = i + 1
    end

    self:set_keepalive(db)
    return multi_resultset
end

local function _do_transaction(db, sqls)
    local multi_resultset = {}

    for i, sql in ipairs(sqls) do
        local res, err, errcode, sqlstate = _M:query_db(db, sql)
        if not res then
            ngx.log(ngx.ERR, "bad result #", i, ": ", err, ": ", errcode, ": ", sqlstate, ",sql=", sql)
            return nil, err, errcode, sqlstate
        end

        if not (type(res.affected_rows) == "number" and res.affected_rows > 0) then
            ngx.log(ngx.ERR, "no affected #", i, ",sql=", sql)
            return nil, "no affected", _M.NO_AFFECTED
        end

        table.insert(multi_resultset, res)
    end

    return multi_resultset
end

-- 执行事务
-- 返回 [{ insert_id = 0, server_status = 2, warning_count = 1, affected_rows = 32, message = nil}]
function _M:transaction(sqls)
    local db, err, errcode, sqlstate = self:connect()
    if not db then
        return nil, err, errcode, sqlstate
    end

    local res
    res, err, errcode, sqlstate = self:query_db(db, "start transaction;")
    if not res then
        return nil, err, errcode, sqlstate
    end

    res, err, errcode, sqlstate = _do_transaction(db, sqls)
    if not res then
        self:query_db(db, "rollback;")
    else
        self:query_db(db, "commit;")
    end

    if res or errcode == _M.NO_AFFECTED then
        self:set_keepalive(db)
    end

    return res, err, errcode, sqlstate
end


return _M






