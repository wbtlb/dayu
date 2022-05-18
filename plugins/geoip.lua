local cjson               = require 'cjson'
local geo                 = require 'resty.maxminddb'
--local ngx_var_remote_addr = ngx.var.remote_addr
--local headers             = ngx.req.get_headers()
local ngx_re            = require "ngx.re"
local ngx_re_split      = ngx_re.split
local string_gmatch     = string.gmatch


local libmaxmind_path = '/usr/local/share/GeoIP/GeoIP2-City.mmdb'
--local remote_addr = headers["X-REAL-IP"] or headers["X_FORWARDED_FOR"] or ngx_var_remote_addr

local _M = {}

function is_private_ip(ip)
    local ip_decimal = 0
    local postion = 3
    for i in string_gmatch(ip, [[%d+]]) do
        ip_decimal = ip_decimal + math.pow(256, postion) * i
        postion = postion - 1
    end
    
    if ip_decimal >= 0x7f000000 and ip_decimal <= 0x7fffffff or
        ip_decimal >= 0x0a000000 and ip_decimal <= 0x0affffff or
        ip_decimal >= 0xac100000 and ip_decimal <= 0xac1fffff or
        ip_decimal >= 0xc0a80000 and ip_decimal <= 0xc0a8ffff then
        return true
    else
        return false
    end
end

local function get_geo_data(remote_addr)
    --local remote_addr = "100.96.39.182"
    if not geo.initted() then
        geo.init(libmaxmind_path)
    end
    if is_private_ip(remote_addr) == true then
        return nil, nil
    end
    local res, err = geo.lookup(remote_addr)
    if not res then
        return nil, err
    end
    return res, nil
end

function _M.set_geo_header(remote_addr)
    local res, err = get_geo_data(remote_addr)
    if res ~= nil and err == nil then
        ngx.req.set_header("geoip-country-code", res["country"]["iso_code"] or nil)
        ngx.req.set_header("geoip-location-time-zone", res["location"]["time_zone"] or nil)
        ngx.req.set_header("geoip-location-longitude", res["location"]["longitude"] or nil)
        ngx.req.set_header("geoip-location-latitude", res["location"]["latitude"] or nil)
    elseif res == nil and err == nil then
        return 
    else
        ngx.log(ngx.ERR, "get geoip data failed: ", err)
        return
    end
end

return _M
