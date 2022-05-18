# 动态流量网关
&emsp;&emsp;该系统是基于 openresty 开发的动态 upstream 流量网关.该系统基于 consul kv 做 upstream 配置管理.实现了无需 reload nginx 即可动态上下线上游服务器.

## 1. 支持功能

- [x] 动态 upstream
- [x] roundrobin 轮循策略
- [x] chash 轮循策略
- [x] 基于 consul 配置管理
- [x] 被动健康检查
- [x] 主动健康检查
- [x] api 配置管理
- [x] dashboard 管理界面
- [x] fastcgi proxy pass
- [x] geoip
- [x] 插件动态热加载/卸载

## 2. 依赖库

|依赖库|git 仓库|说明|
|------|--------|----|
|lua-resty-http|https://github.com/ledgetech/lua-resty-http.git|http 依赖库|
|lua-resty-balancer|https://github.com/openresty/lua-resty-balancer.git|负载均衡依赖库|
|lua-resty-healthcheck|https://github.com/Kong/lua-resty-healthcheck.git|健康检查依赖库|

## 3. 部署安装及配置
### 3.1 部署安装

### 3.2 配置

1. consul upstream 配置示例
```
{
    "server": [
        {
            "host": "10.11.14.54:801",
            "weight": 1
        },
        {
            "host": "10.11.14.54:802",
            "weight": 1
        }
    ],
    "resolver": {
        "nameservers": ["10.11.16.10"],
        "retrans": 5,
        "timeout": 2000,
        "ttl": 600
    },
    "retries":3, 
    "healthcheck":{
        "active": {
            "type":"http",
            "http_path":"/",
            "healthy": {
                "interval": 2,
                "successes": 1
            },
            "unhealthy": {
                "interval": 1,
                "http_failures": 2
            }
        },
        "passive":{
            "healthy":{
                "successes":3
            },
            "unhealthy":{
                "timeouts": 5, 
                "http_failures":10, 
                "tcp_failures":3
            }
        }
    }
}
```
2. nginx.conf 配置示例
```
# 共享字典配置
lua_shared_dict prometheus_metrics 10M;
lua_shared_dict ngx_ups_list 10M;
lua_shared_dict healthcheck 1m;
lua_shared_dict test_shm 8m;
lua_shared_dict my_worker_events 8m;
lua_shared_dict worker_events 5m;
lua_shared_dict process_events 1m;

# 打开获取请求 body
lua_need_request_body on;
# 打开代码缓存
lua_code_cache on;

# 配置 lua 代码加载路径
lua_package_path "/usr/local/dayu/?.lua;/usr/share/lua/5.1/?.lua;;";
# 配置动态库路径
lua_package_cpath "/usr/local/openresty/lib/?.so;/usr/lib64/lua/5.1/socket/?.so;;"; 

# 上游 upstream
upstream backend {
    server 0.0.0.1;
    balancer_by_lua_block {
        local balancer = require "balancer";
        balancer.balancer_run();
    }
}

# keepalived 64 上游 upstream
upstream backend_keepalive_64 {
    server 0.0.0.1;
    balancer_by_lua_block {
        local balancer = require "balancer";
        balancer.balancer_run();
    }
    keepalive 64;
}

# 初始化配置, 从 consul 加载配置
init_worker_by_lua_block {
    local config = require "config";
    config.init()
}

# 打开 prometheus metrics 收集
log_by_lua_block {
    local monitor = require "prometheus"
    monitor.metrics()
}

# 打开添加 geoip 数据到 header 中
rewrite_by_lua_block {
    local lru_middware = require "middware"
    local lplugin = lru_middware.plugins
    local ngx_var_remote_addr = ngx.var.remote_addr
    local headers             = ngx.req.get_headers()
    local remote_addr = headers["X-REAL-IP"] or headers["X_FORWARDED_FOR"] or ngx_var_remote_addr

    local geo = lplugin:get("geoip")
    if geo ~= nil then
        geo.set_geo_header(remote_addr)
    end
}

# 管理 API 入口
server {
    listen 8001;                                                                                  

    location /admin/ {
        content_by_lua_file /usr/local/dayu/admin/index.lua;
    }
}


# 一个 server 配置
server {
    listen 80;
    server_name s.subcdn.com; 
    location /aaa {
# 配置上游服务上下文
        access_by_lua_block {
          	ngx.ctx.upstream_name = "s-subcdn-com"
        }
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://backend; 
        #proxy_pass http://backend_keepalive_64; 
    }

}

```

## 4. 健康检查配置参数
### 4.1 支持参数列表
|参数|说明|
|----|----|
|checks.active.type|"http", "https" or "tcp" (default is "http")|
|checks.active.timeout|socket timeout for active checks (in seconds)|
|checks.active.concurrency|number of targets to check concurrently|
|checks.active.http_path|path to use in GET HTTP request to run on active checks|
|checks.active.https_verify_certificate|boolean indicating whether to verify the HTTPS certificate|
|checks.active.healthy.interval|interval between checks for healthy targets (in seconds)|
|checks.active.healthy.http_statuses|which HTTP statuses to consider a success|
|checks.active.healthy.successes|number of successes to consider a target healthy|
|checks.active.unhealthy.interval|interval between checks for unhealthy targets (in seconds)|
|checks.active.unhealthy.http_statuses|which HTTP statuses to consider a failure|
|checks.active.unhealthy.tcp_failures|number of TCP failures to consider a target unhealthy|
|checks.active.unhealthy.timeouts|number of timeouts to consider a target unhealthy|
|checks.active.unhealthy.http_failures|number of HTTP failures to consider a target unhealthy|
|checks.passive.type|"http", "https" or "tcp" (default is "http"; for passive checks, "http" and "https" are equivalent)|
|checks.passive.healthy.http_statuses|which HTTP statuses to consider a failure|
|checks.passive.healthy.successes|number of successes to consider a target healthy|
|checks.passive.unhealthy.http_statuses|which HTTP statuses to consider a success|
|checks.passive.unhealthy.tcp_failures|number of TCP failures to consider a target unhealthy|
|checks.passive.unhealthy.timeouts|number of timeouts to consider a target unhealthy|
|checks.passive.unhealthy.http_failures|number of HTTP failures to consider a target unhealthy|

### 4.2 参数配置路径示例

```
"healthcheck":{
    "active": {
        "type":"http",
        "http_path":"/",
        "healthy": {
            "interval": 2,
            "successes": 1
        },
        "unhealthy": {
            "interval": 1,
            "http_failures": 2
        }
    },
    "passive":{
        "healthy":{
            "successes":3
        },
        "unhealthy":{
            "timeouts": 5, 
            "http_failures":10, 
            "tcp_failures":3
        }
    }
}
```

## 5. TODO
- [ ] 证书管理
- [ ] 动态路由管理

## 6. Benchmark

### 6.1 压测

压测场景: 阿里云 ecs.hfg5.2xlarge 8 vCPU 32 GiB, 4 Nginx worker,关闭 prometheus.
```
# wrk  -c 500  --latency 'http://s.subcdn.com/aaa'
Running 10s test @ http://s.subcdn.com/aaa
  2 threads and 500 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     9.44ms    4.38ms  77.97ms   82.37%
    Req/Sec    27.11k     1.80k   29.84k    76.00%
  Latency Distribution
     50%    8.16ms
     75%   11.20ms
     90%   14.96ms
     99%   25.80ms
  539254 requests in 10.03s, 94.60MB read
Requests/sec:  53782.14
Transfer/sec:      9.43MB
```

压测场景: 阿里云 ecs.c5.xlarge 4 vCPU 8GiB, 4 Nginx worker,关闭 prometheus.
```
# wrk  -c 800  --latency 'http://s.subcdn.com/aaa'
Running 10s test @ http://s.subcdn.com/aaa
  2 threads and 800 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    32.24ms   85.53ms   1.04s    97.71%
    Req/Sec    18.81k   655.05    19.84k    83.50%
  Latency Distribution
     50%   19.29ms
     75%   25.37ms
     90%   34.90ms
     99%  555.90ms
  374296 requests in 10.05s, 65.66MB read
Requests/sec:  37237.03
Transfer/sec:      6.53MB
```

压测场景: 阿里云 ecs.c5.xlarge 4 vCPU 8GiB, 1 Nginx worker, 关闭 prometheus.
```
# wrk  -c 300  --latency 'http://s.subcdn.com/aaa'
Running 10s test @ http://s.subcdn.com/aaa
  2 threads and 300 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    19.15ms   20.22ms 338.03ms   96.60%
    Req/Sec     9.10k   370.28     9.90k    69.50%
  Latency Distribution
     50%   15.91ms
     75%   17.44ms
     90%   19.24ms
     99%  134.69ms
  181010 requests in 10.02s, 31.75MB read
Requests/sec:  18068.22
Transfer/sec:      3.17MB
```

### 6.2 火焰图

![Lua Nginx Modules Directives](https://git.apuscn.com:8443/sa/dayu/-/raw/master/benchmark/imgs/flame-g-c.png)
![Lua Nginx Modules Directives](https://git.apuscn.com:8443/sa/dayu/-/raw/master/benchmark/imgs/flame-g-l.png)
