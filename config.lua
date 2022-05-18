local req               = require "lib.http"
local cjson             = require("cjson.safe").new()
local base64            = require "ngx.base64"
local resty_roundrobin  = require "resty.roundrobin"
local healthcheck       = require "resty.healthcheck"
local we                = require "resty.worker.events"
local ngx_re            = require "ngx.re"
-- 加载 consul 配置信息
local config            = require "etc.config"
local lrucache_c        = require "middware"
local monitor           = require "prometheus"
local ngx_re            = require "ngx.re"
local ngx_re_split      = ngx_re.split
local b64_decode        = base64.decode_base64url
local ngx_timer_at      = ngx.timer.at
local ups_list          = lrucache_c.ups_list
local ori_value         = lrucache_c.ori_value
local resolver          = require "dns_resolver"
local ipairs            = ipairs
local exiting           = ngx.worker.exiting

assert(we.configure{shm = "my_worker_events", interval = 0.1})

local DEFAULT_HOST  = "192.168.0.123"
local DEFAULT_PORT  = "8500"
local API_VERSION   = "v1"

local _M = {
    _VERSION = "0.0.1"
}

local store_config = {
    consul = {
        api_prefix = "/v1/kv",
        keys = {
            prefix = "/?keys",
            list = function(resp)
                return cjson.decode(resp.body)
            end
        },
        list = {
            extract = function(value)
                local value_table = {}
                if value ~= nil then
                    local value_str = b64_decode(value)
                    if value_str ~= nil then
                        table.insert(value_table, value_str)
                    end
                end
                return value_table
            end,
        }
    }
}

function balancer_init(value_table)
    local upstream = {upslist={}, backuplist={}, checks = {}}
    local server_list = {}

    local ups_list = value_table["server"]["primary"]
    local backup_list = value_table["server"]["backup"] or {}
    local dns_resolver
    if value_table.resolver ~= cjson.null  then
        dns_resolver = resolver:new(value_table.resolver)
    end
    upstream["retries"] = value_table["retries"]
    upstream["checks"] = value_table["healthcheck"]
    upstream["hash"] = value_table["hash"]

    local balancer_type = nil;
    -- support chash type: remote_ip and uri

    if backup_list ~= cjson.null then
        for _, ups in ipairs(backup_list) do
            local host = ngx_re_split(ups["host"], ":")[1]
            local iter = string.gmatch(host, "(%d+%.%d+%.%d+%.%d+)")
            --local skey = string.format("[%s]", ups["host"])
            if iter() == nil then
                if dns_resolver then
                    host = dns_resolver:query(host, nil, {}).value
                else
                    ngx.log(ngx.ERR, "nginx create resolver failed.")
                    return
                end
            end
            local hp = {
                --host = ngx_re_split(ups["host"], ":")[1],
                host = host,
                port = tonumber(ngx_re_split(ups["host"], ":")[2]),
                weight = ups["weight"] or 1,
            }
            upstream["backuplist"][ups["host"]] = hp
            ---server_list[skey] = weight
        end
    end

    for _, ups in ipairs(ups_list) do
        --local skey = string.format("[%s]", ups["host"])
        local host = ngx_re_split(ups["host"], ":")[1]
        local iter = string.gmatch(host, "(%d+%.%d+%.%d+%.%d+)")


        if iter() == nil then
            if dns_resolver then
                host = dns_resolver:query(host, nil, {}).value
            else
                ngx.log(ngx.ERR, "nginx create resolver failed.")
                return
            end
        end
        local hp = {
            --host = ngx_re_split(ups["host"], ":")[1],
            host = host,
            port = tonumber(ngx_re_split(ups["host"], ":")[2]),
            weight = ups["weight"] or 1
        }
        upstream["upslist"][ups["host"]] = hp
        ---server_list[skey] = weight
    end
    --ngx.log(ngx.ERR, "TTTTTTTTTTT", cjson.encode(upstream))
    --upstream["server_list"] = server_list 
     
    return upstream
end


local function load_ups_config(v)
    local key = v["Key"]
    local value = v["Value"]  
    
    local value_tables = store_config.consul.list.extract(value)
    for _, value in pairs(value_tables) do
        local value_table = cjson.decode(value)

        local sv = ngx_re_split(key, "/")
        if value_table ~= nil then
            value_table["skey"] = key

            local upstream = balancer_init(value_table)
            upstream["skey"] = key
            ori_value[key] = upstream
            ups_list:set(key, upstream)

            local upstream_str = cjson.encode(upstream)
            local ok, err = ngx.shared.ngx_ups_list:safe_set(key, upstream_str)
            if err ~= nil then
                ngx.log(ngx.ERR, "failed to load config to shared dict: ", err)
            end
        end
    
    end
end

local function get_consul_url()
    local host = config.store.host
    local port = config.store.port
    local prefix = "/"..config.store.prefix
    local endpoint = ""
    
    if host == nil then
        ngx.log(ngx.ERR, "get consul endpoint nil")
        return ngx.exit(500)
    end

    if port == nil then
        endpoint = host
    else
        endpoint = host .. ":" .. port
    end

    local base_url = endpoint..store_config.consul.api_prefix..prefix.."/?recurse=true"
    return base_url
end

local function diff_table(a, b)
    local r = {}
    for k, v in pairs(b) do
        if a[k] == nil then
            r[k] = v
        end
    end
    return r
end

local KEY_INDEX = {}
local last_modify_index = 0
local function preload_upstream_keys()
    
    local watch_url = get_consul_url() .. "&wait=60s&index=" .. last_modify_index
    local wres, werr = req.get(watch_url)
    if werr ~= nil then
        ngx.log(ngx.ERR, "get consul data failed!")
    end
    if wres == nil or wres.body == nil then
        ngx.log(ngx.INFO, "there is no update")
        return
    else
        local tmp_table = {}
        local wres_body = cjson.decode(wres.body) 
       
        for _, vv in pairs(wres_body) do
            if KEY_INDEX[vv.Key] == nil then
                KEY_INDEX[vv.Key] = vv.ModifyIndex
            end
            if tonumber(vv["ModifyIndex"]) > tonumber(last_modify_index) then
                local load_value = load_ups_config(vv)
                ngx.log(ngx.INFO, "this key is update, start reload: ", vv["Key"])
            end
            tmp_table[vv.Key] = vv.ModifyIndex
        end
        local rr = diff_table(tmp_table, KEY_INDEX)
        if next(rr) ~= nil then
            for k, m in pairs(rr) do
                ngx.shared.ngx_ups_list:delete(k)
                ups_list:delete(k)
                ori_value[k] = nil
                ngx.log(ngx.INFO, " this key is removed: ", k)
                KEY_INDEX[k] = nil
            end
        end
        local x_consul_index = tonumber(wres.headers["X-Consul-Index"])
        if x_consul_index < last_modify_index then
            last_modify_index = 0
        else
            last_modify_index = x_consul_index
        end
    end
end

local delay = 0
local handler
handler = function (premature)
    if premature then
        return
    end

    preload_upstream_keys()

    if not exiting() then
        local ok, err = ngx.timer.at(delay, handler)
            if not ok then
                ngx.log(ngx.ERR, "failed to create the timer: ", err)
            return
        end
    end
    

end

function _M.init()
    --if 0 == ngx.worker.id() then
    local ok, err = ngx.timer.at(delay, handler)
    if not ok then
        ngx.log(ngx.ERR, "failed to create the timer: ", err)
        return
    end
    local ps = require "plugins.init"
    ps.load_plugins()
    --end
    --monitor.init()
end

return _M
