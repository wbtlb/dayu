local resty_roundrobin = require "resty.roundrobin"
local ljson_decoder    = require "resty.json_decoder"
local decoder          = ljson_decoder.new()
local resty_chash      = require "resty.chash"
local cjson            = require("cjson.safe").new()
--local cjson            = require "cjson"
local balancer         = require "ngx.balancer"
local ngx_re           = require "ngx.re"
local ngx_re_split     = ngx_re.split
local config           = require "etc.config"
local healthcheck      = require "resty.healthcheck"
local ngx_ups_list     = ngx.shared.ngx_ups_list
local lrucache_c       = require "middware"
local c                = lrucache_c.c
local lchecker         = lrucache_c.checker
local lupstream        = lrucache_c.upstream_table
local lpicker          = lrucache_c.picker
local lbackup          = lrucache_c.lbackup_list
local ori_value        = lrucache_c.ori_value
local host_header      = ngx.var.http_host
local server_name      = ngx.var.server_name
local ngx_var_uri      = ngx.var.uri
local string           = string
local pairs            = pairs
local set_more_tries   = balancer.set_more_tries
local log              = ngx.log
local headers          = ngx.req.get_headers()
local next             = next
local new_tab          = require("table.new")
local ngx_var_remote_addr = ngx.var.remote_addr
local isempty          = require("table.isempty")
local ups_list         = lrucache_c.ups_list
local gsub             = string.gsub
local char             = string.char


local v = require "jit.v"
v.on("/tmp/jit.log")
local _M = {}

--local ffi = require("ffi")
--
--ffi.cdef[[
--    struct timeval {
--        long int tv_sec;
--        long int tv_usec;
--    };
--    int gettimeofday(struct timeval * tv, void * tz);
--]];
--
--local tm = ffi.new("struct timeval")
--
--function current_time_millis()
--    ffi.C.gettimeofday(tm, nil)
--    local sec = tonumber(tm.tv_sec)
--    local usec = tonumber(tm.tv_usec)
--    return sec + usec * 10^-6
--end
--local upstream = {}

--local upstream = {upslist={}, checks={}}

--[[
upstream = 
{   
    "retries":3,
    "btype":"roundrobin",
    "server_list":{"[192.168.0.123:802]":3,"[192.168.0.123:801]":3},
    "checks":{
        "passive":{
            "unhealthy":{
                "tcp_failures":3,
                "http_failures":3
                },
            "healthy":
                {"successes":1
            }
        }
    },
    "upslist":{
        "[192.168.0.123:802]":{"host":"192.168.0.123","port":"802"},
        "[192.168.0.123:801]":{"host":"192.168.0.123","port":"801"}
    },
    "skey":"vm-proxy\/upstreams\/test001"
}
--]]

local function parse_upslist(upslist)
    local up_nodes = {}
    for addr, node in pairs(upslist) do
    	local ip = node.host
    	local port = node.port
        up_nodes[addr] = node.weight
    end
    return up_nodes
end


-- 取出健康节点, 加入负载均衡轮循机器列表
local function fetch_healthy_nodes(name, upstream)
    local up_nodes = new_tab(0, 64)
    local checker = lchecker:get(name)
   
    for addr, node in pairs(upstream.upslist) do
    	local ip = node.host
    	local port = node.port
        --local ip, port = parse_addr(addr)
        local ok, err = checker:get_target_status(ip, port, server_name)

        if ok then
            up_nodes[addr] = node.weight
        end   
    end
    
    if isempty(up_nodes) then
        for addr, node in pairs(upstream.upslist) do
            up_nodes[addr] = node.weight
        end
        --if isempty(upstream.backuplist) then
        --    for addr, node in pairs(upstream.upslist) do
        --        up_nodes[addr] = node.weight
        --    end
        --else
        --    for addr, node in pairs(upstream.backuplist) do
        --        up_nodes[addr] = node.weight
        --    end
        --end
    end
    return up_nodes
end

local function create_checker(name, upstream)
    local checker, err = healthcheck.new({
        name = name,
        shm_name = "healthcheck",
        checks = upstream["checks"]
    })
    if err ~= nil then
	    ngx.log(ngx.ERR, "create checker err: ", err)
    end
    for _, v in pairs(upstream.upslist) do
        local ok, err = checker:add_target(v["host"], tonumber(v["port"]), server_name, true)
        
        if not ok then
            ngx.log(ngx.ERR, "failed to add new health check target: ", v["host"], " err: ", err)
        end
    end
    lchecker:set(name, checker, 120)
end

local function get_hash_key(hash_field)
    local hash_key
    local remote_addr = headers["X-REAL-IP"] or headers["X_FORWARDED_FOR"] or ngx_var_remote_addr

    if hash_field == "remote_ip" then
        hash_key = remote_addr
    elseif hash_field == "uri" then
        hash_key = ngx_var_uri
    else
        hash_key = remote_addr
    end
    return hash_key
end

local function set_roundrobin(up_nodes, upstream)
    local rr_up = resty_roundrobin:new(up_nodes)
    local ups_server_list
    ups_server_list = {
        upstream = upstream,
        get = function()
            return rr_up:find()
        end
    }
    return ups_server_list
end

--local healthy_node_length
local function set_ups_server_list(name, upstream)
    local checker, old_checker = lchecker:get(name)
    if checker == nil then
        if old_checker then
            old_checker:clear()
            old_checker:stop()
        end
        create_checker(name, upstream)
    end
    local up_nodes = fetch_healthy_nodes(name, upstream)
    --ngx.shared.healthnode:safe_set(upstream["skey"], cjson.encode(server_list), 5)
    local btype = upstream["btype"]
    local hash_field = upstream["hash"] or "remote_ip"
    local ups_server_list

    if btype == nil or btype == "roundrobin" then
        return set_roundrobin(up_nodes, upstream)
        --local rr_up = resty_roundrobin:new(up_nodes)

        --ups_server_list = {
    --    upstream = upstream,
    --    get = function()
    --    return rr_up:find()
    --    end
        --}
        ----local ok, err = c:set(name, ups_server_list, 30)
        ----if err ~= nil then
        ----	ngx.log(ngx.ERR, "roundrobin set upstream server list failed: ", err)
        ----	return
        ----end
        --return ups_server_list
    elseif btype == "remote_ip" or btype == "uri" then
        local str_null = char(0)

        local servers, nodes = {}, {}
        for serv, weight in pairs(up_nodes) do
            local id = gsub(serv, ":", str_null)
            servers[id] = serv
            nodes[id] = weight
        end
        local chash_up = resty_chash:new(nodes)
        ups_server_list = {
            upstream = upstream,
            get = function()
            --local id = chash_up:find(ngx.ctx.chash_key)
                local hash_key = get_hash_key()
                local id = chash_up:find(hash_key)
                return servers[id]
            end
        }
        --local ok, err = c:set(name, ups_server_list, 30)
        --if err ~= nil then
        --	ngx.log(ngx.ERR, "hash set upstream server list failed: ", err)
        --        return
       	--end
       	return ups_server_list 
    else
        ngx.log(ngx.ERR, "Invalid balance method.")
        return 
    end
end

local function pick_server(ctx, name)
    local checker = lchecker:get(name)
    local ups_data = c:get(name)
    if ups_data == nil then
        local upstream = ori_value[name] 
        if upstream  == nil then
            local upstream_str = ngx_ups_list:get(name)
            if upstream_str == nil then
                return
            end
            upstream = decoder:decode(upstream_str)
	    end
        --upstream = get_loadbalancer_method(upstream)
        ups_data = set_ups_server_list(name, upstream)
        c:set(name, ups_data, 10)
    end
    local upstream = ups_data.upstream
    local retries = upstream.retries or 1
    if retries and retries > 0 then
        ctx.balancer_try_count = (ctx.balancer_try_count or 0) + 1
        --if checker and ctx.balancer_try_count > 1 then
        if ctx.balancer_try_count > 1 then
            --local checker
            if checker then
                --local skey = ctx.balancer_ip .. ":" .. ctx.balancer_port
                local state, code = balancer.get_last_failure()
                if state == "failed" then
                    if code == 504 then
                        checker:report_timeout(ctx.balancer_ip, ctx.balancer_port, server_name)
                    else
                        checker:report_tcp_failure(ctx.balancer_ip, ctx.balancer_port, server_name, "passive")
                        --c:delete(name)
                    end
                else
                    checker:report_http_status(ctx.balancer_ip, ctx.balancer_port, server_name, code, "passive")
                end
            end
            if isempty(upstream.backuplist) == false then
                local state, code = balancer.get_last_failure()
                if state == "failed" and code ~= 504 then
                    local backup_list = parse_upslist(upstream.backuplist)
                    local backup, err = lbackup:get(name)
                    if backup == nil then
                        backup = set_roundrobin(backup_list, upstream)
                        lbackup:set(name, backup, 30)
                    end
                    local server = backup:get()
                    local ip = ngx_re_split(server, ":")[1]
                    local port = ngx_re_split(server, ":")[2]
                    ctx.balancer_ip = ip
                    ctx.balancer_port = port
                    set_more_tries(retries)
                    return ip, port
                end
            end
        end

        if ctx.balancer_try_count == 1 then
            set_more_tries(retries)
        end
    end

    local server = ups_data:get()
    local ip = ups_data.upstream["upslist"][server]["host"]
    local port = ups_data.upstream["upslist"][server]["port"]
   
    ctx.balancer_ip = ip
    ctx.balancer_port = port
    return ip, port 
end

function _M.balancer_run()
    local ctx = ngx.ctx
    local upstream_name = ctx.upstream_name
    local lskey = config.store.prefix .. '/' .. upstream_name
    --local upstream_str = ngx_ups_list:get(lskey)

    --local upstream = lupstream:get(lskey)
    --if upstream == nil then
    --	local upstream_str = ngx_ups_list:get(lskey)
    --    upstream = decoder:decode(upstream_str)
    --    upstream = get_loadbalancer_method(upstream)	
    --    lupstream:set(lskey, upstream, 30)
    --end

    --local upstream = ups_list:get(lskey)
    --if upstream == nil then

    --    ups_list:set(lskey, upstream, 30)
    --end
    
    local ip, port = pick_server(ctx, lskey)
    if ip == nil or port == nil then
        ngx.exit(502)
        return
    end
    local ok, err = balancer.set_current_peer(ip, port)
    if not ok then
        ngx.exit(502)
    end
end

return _M
