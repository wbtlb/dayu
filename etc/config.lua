local _M = {}

_M.store = {
    stype = "consul",
    host = "http://192.168.0.123",
    port = "8500",
    prefix = "test/vm-qa/upstreams",
}

--_M.plugins = {
--    ["geoip"] = "on"
--}

return _M
