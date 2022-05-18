local _M = {}

local lrucache = require "resty.lrucache"

function _M.new()
    local c, err = lrucache.new(200)
    if not c then
        ngx.log(ngx.ERR, "failed to new lrucache: ", err)
        return
    end
    return c
end

function _M.set(key, value)
    c:set(key, value)
end

function _M.get(key)
    return c:get(key)
end

return _M
