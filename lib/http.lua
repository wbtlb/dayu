local http = require("resty.http")
local cjson = require("cjson")

local _M = {}

function _request(method, url, body, headers, args)
    local httpc = http.new()
    httpc:set_timeouts(60000,60000,600000)
    local res, err = httpc:request_uri(url, {
        method = method,
        headers = {
            [""] = "",
        },
        keepalive_timeout = 600,
        keepalive_pool = 10,
    })
    if err ~= nil then
        ngx.log(ngx.ERR, "failed to request, err:", err)
        return
    end
    return res, nil
end

function _M.get(url, body, headers)
    local res, err = _request("GET", url, headers)
    if err ~= nil then
        ngx.log(ngx.ERR, "failed to get, err: ", err)
        return
    end

    return res, nil
end

return _M
