prometheus = require("resty.prometheus").init("prometheus_metrics")

local _M = {}

function _M.init()

    metric_requests = prometheus:counter(
        "nginx_http_requests_total", "Number of HTTP requests", {"host", "status"}
    )
    -- 域名请求流量
    metric_bytes_sent = prometheus:counter(
        "nginx_bytes_sent", "Number of byte send to client", {"host"}
    )
    
    -- upstream 响应耗时
    metric_upstream_response_time = prometheus:counter(
        "nginx_upstream_response_time", "Upstream response time", {"host"}
    )
    
    -- 域名请求耗时
    metric_request_time = prometheus:counter(
        "nginx_request_time", "Time of HTTP Requests", {"host"}
    )
    
    --metric_latency = prometheus:histogram(
    --    "nginx_http_request_duration_seconds", "HTTP request latency", {"host"}
    --)
    
    metric_connections = prometheus:gauge(
        "nginx_http_connections", "Number of HTTP connections", {"state"}
    )
    
    request_length = prometheus:counter(
        "nginx_http_request_length", "Total size of request length", {"domain"}
    )

    request_bytes_sent = prometheus:counter(
        "nginx_http_request_bytes_sent", "Total size of body sent bytes", {"domain"}
    )
    
    upstream_metric_requests = prometheus:counter(
        "nginx_upstream_requests", "Number of HTTP upstream connections", {"upstream_addr", "domain", "upstream_status"}
    )
    
    upstream_bytes_received = prometheus:counter(
        "nginx_upstream_bytes_received", "Total size of upstream received bytes", {"upstream_addr", "domain"}
    )
    
    upstream_response_length = prometheus:counter(
        "nginx_upstream_response_length", "Total size of upsream response length", {"upstream_addr", "domain"}
    )
end

function _M.metrics()
    local server_name = ngx.var.http_host
    local ngx_var_status = ngx.var.status
    local ngx_var_host = ngx.var.host
    local ngx_var_request_length = ngx.var.request_length
    local ngx_var_bytes_sent = ngx.var.bytes_sent
    local ngx_var_upstream_addr = ngx.var.upstream_addr
    local ngx_var_upstream_bytes_received = ngx.var.upstream_bytes_received
    local ngx_var_upstream_response_length = ngx.var.upstream_response_length 
    local ngx_var_upstream_status = ngx.var.upstream_status

    metric_requests:inc(1, {server_name, ngx_var_status})
    metric_bytes_sent:inc(ngx.var.bogy_bytes_sent, {server_name})
    --metric_upstream_response_time:inc()                                                                                               
    ----metric_latency:observe(tonumber(ngx.var.request_time), {server_name})

    request_length:inc(tonumber(ngx_var_request_length), {server_name})
    request_bytes_sent:inc(tonumber(ngx_var_bytes_sent), {server_name})
    if ngx_var_upstream_addr ~= nil then
        upstream_metric_requests:inc(1, {ngx_var_upstream_addr, server_name, ngx_var_upstream_status})
        upstream_bytes_received:inc(tonumber(ngx_var_upstream_bytes_received), {ngx_var_upstream_addr, server_name})
        upstream_response_length:inc(tonumber(ngx_var_upstream_response_length), {ngx_var_upstream_addr, server_name})
    end

end

return _M
